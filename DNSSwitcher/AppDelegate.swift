//
//  AppDelegate.swift
//  DNSSwitcher
//
//  Created by Matthew McNeeney on 02/06/2016.
//  Copyright © 2016 mattmc. All rights reserved.
//

import Cocoa
import SwiftyJSON

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    @IBOutlet weak var menu: NSMenu!
    @IBOutlet weak var versionItem: NSMenuItem!

    let statusItem = NSStatusBar.systemStatusBar().statusItemWithLength(-1)
    let configFilePath = NSHomeDirectory().stringByAppendingString("/.dnsswitcher.json")

    var config: Config?
    var lastConfigFileUpdate: NSDate?

    // MARK: - Application lifecycle

    func applicationDidFinishLaunching(aNotification: NSNotification) {

        // Add status bar icon
        let menuIcon = NSImage(named: "MenuIcon")
        menuIcon?.template = true
        statusItem.image = menuIcon
        statusItem.menu = menu

        // Set version number
        if let version = NSBundle.mainBundle().infoDictionary!["CFBundleShortVersionString"] as? String {
            self.versionItem.title = "v\(version)"
        }

        // Create default configuration file if required
        if !NSFileManager.defaultManager().fileExistsAtPath(self.configFilePath) {
            self.createDefaultConfigFile()
        }

        // Make sure we know whenever the menu is opened
        self.menu.delegate = self
    }


    // MARK: - Initialisation

    func initMenu() {

        guard let configData = NSData(contentsOfFile: self.configFilePath) else {
            print("Critical error: configuration file failed to load")
            self.quit(nil)
            return
        }

        // Create the configuration object
        self.config = Config(data: configData)

        // Clear existing servers from the menu
        self.clearServers()

        // Add the new list of servers to the menu
        for setting in self.config!.settings!.reverse() {

            // Add the name of the DNS server as the menu title
            let item = DNSMenuItem(title: setting.name!, action: nil, keyEquivalent: "")

            // Create the submenu
            let submenu = NSMenu()

            // Add a load button
            let loadItem = DNSMenuItem(title: "Load", action: #selector(AppDelegate.setDNSServers(_:)), keyEquivalent: "")
            loadItem.setting = setting
            submenu.addItem(loadItem)

            // Add a separator
            submenu.addItem(NSMenuItem.separatorItem())

            // Add the adapter name and list of servers
            let adapterItem = NSMenuItem(title: "Interface: \(setting.interface!)", action: nil, keyEquivalent: "")
            adapterItem.enabled = false
            submenu.addItem(adapterItem)
            let serverTitleItem = NSMenuItem(title: "Servers:", action: nil, keyEquivalent: "")
            serverTitleItem.enabled = false
            submenu.addItem(serverTitleItem)
            for server in setting.servers! {
                let item = NSMenuItem(title: server, action: nil, keyEquivalent: "")
                item.enabled = false
                submenu.addItem(item)
            }

            // Add the submenu to the menu item
            item.submenu = submenu

            // Add the menu item to the top of the menu
            self.menu.insertItem(item, atIndex: 0)
        }
    }

    func clearServers() {
        for item in self.menu.itemArray {
            if item is DNSMenuItem {
                self.menu.removeItem(item)
            }
        }
    }

    func createDefaultConfigFile() {
        // If the file doesn't exist, create it using the default
        if !NSFileManager.defaultManager().fileExistsAtPath(self.configFilePath) {
            let defaultFilePath = NSBundle.mainBundle().pathForResource("dnsswitcher.default", ofType: "json")
            do {
                try NSFileManager.defaultManager().copyItemAtPath(defaultFilePath!, toPath: self.configFilePath)
            }
            catch {
                print("Critical error: failed to create default config file")
                self.quit(nil)
            }
        }
        // Else copy the contents of the default to the existing file
        let defaultFilePath = NSBundle.mainBundle().pathForResource("dnsswitcher.default", ofType: "json")
        let data = NSData(contentsOfFile: defaultFilePath!)
        data?.writeToFile(self.configFilePath, atomically: true)
    }

    func checkForConfigUpdate() -> Bool {
        // Check when the configuration file was last modified
        var configFileAttributes: [String: AnyObject]?
        do {
            configFileAttributes = try NSFileManager.defaultManager().attributesOfItemAtPath(self.configFilePath)
        }
        catch _ {
            // Failover - reload the configuration file
            return true
        }
        guard let lastModification = configFileAttributes?[NSFileModificationDate] as? NSDate else {
            // Failover - reload the configuration file
            return true
        }

        // This may be the first load
        if self.lastConfigFileUpdate == nil {
            self.lastConfigFileUpdate = lastModification
            return true
        }

        // Compare the modification dates
        let updateNeeded = (lastModification.compare(self.lastConfigFileUpdate!) == NSComparisonResult.OrderedDescending)
        self.lastConfigFileUpdate = lastModification
        return updateNeeded
    }


    // MARK: - Menu delegate

    func menuWillOpen(menu: NSMenu) {
        /* If the configuration file has been edited or this is the first load,
         * reload the configuration file */
        if !self.checkForConfigUpdate() {
            return
        }
        self.initMenu()
    }


    // MARK: - Actions

    func setDNSServers(item: DNSMenuItem) {
        let command: [String] = [ "networksetup", "-setdnsservers", item.setting.interface! ] + item.setting.servers!
        let result = runCommand(command)
        if result != 0 {
            print("Error changing DNS servers: \(result)")
        }
    }

    func runCommand(args: [String]) -> Int32 {
        let task = NSTask()
        task.launchPath = "/usr/bin/env"
        task.arguments = args
        task.launch()
        task.waitUntilExit()
        return task.terminationStatus
    }

    @IBAction func editServers(sender: AnyObject) {
        NSWorkspace.sharedWorkspace().openFile(self.configFilePath)
    }

    @IBAction func restoreDefaultServers(sender: AnyObject) {
        self.createDefaultConfigFile()
        self.initMenu()
    }

    @IBAction func about(sender: AnyObject) {
        if let url = NSBundle.mainBundle().infoDictionary!["Product Homepage"] as? String {
            NSWorkspace.sharedWorkspace().openURL(NSURL(string: url)!)
        }
    }

    @IBAction func quit(sender: AnyObject?) {
        NSStatusBar.systemStatusBar().removeStatusItem(statusItem)
        NSApp.terminate(self)
    }

}

