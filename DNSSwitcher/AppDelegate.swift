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
    @IBOutlet weak var interfaceMenu: NSMenu!

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

        // Load available network interfaces
        self.loadNetworkInterfaces()

        // Load the configuration file
        self.initMenu()
    }


    // MARK: - Network interfaces

    func loadNetworkInterfaces() {
        let command: [String] = [ "networksetup", "-listallnetworkservices" ]
        let (result, output) = runCommand(command)
        if result != 0 {
            print("Critical error: could not load network services")
            self.quit(nil)
            return
        }
        for interface in output.componentsSeparatedByString("\n") {
            // Ignore disabled interfaces
            if interface.containsString("*") || interface == "" {
                continue
            }
            // Add the network interface to the interfaces menu
            let interfaceItem = NSMenuItem(title: interface, action: #selector(AppDelegate.setInterface(_:)), keyEquivalent: "")
            self.interfaceMenu.addItem(interfaceItem)
        }
    }

    func highlightEnabledInterface() {
        var interfaceSelected = false
        for item in self.interfaceMenu.itemArray {
            item.state = 0
            if item.title == self.config?.interface {
                item.state = 1
                interfaceSelected = true
            }
        }
        /* Failover - if no interface has been selected, set
         * the first one */
        if !interfaceSelected {
            self.config?.interface = self.interfaceMenu.itemArray[0].title
            self.interfaceMenu.itemArray[0].state = 1
        }
    }

    func setInterface(item: NSMenuItem) {
        self.config?.interface = item.title
        self.highlightEnabledInterface()
        self.saveLatestConfig()
    }


    // MARK: - DNS settings

    func clearServers() {
        for item in self.menu.itemArray {
            if item is DNSMenuItem {
                self.menu.removeItem(item)
            }
        }
    }

    func highlightCurrentDNSServers() {
        let command: [String] = [ "networksetup", "-getdnsservers", self.config!.interface! ]
        let (result, output) = self.runCommand(command)
        if result != 0 {
            print("Error fetching current DNS servers")
            return
        }
        var servers: [String] = []
        for s in output.componentsSeparatedByString("\n") {
            if s != "" {
                servers.append(s)
            }
        }

        // Highlight the selected DNS servers in the menu
        for item in self.menu.itemArray {
            if item is DNSMenuItem {
                item.state = 0
                let setting = (item as! DNSMenuItem).setting
                if setting.servers! == servers {
                    item.state = 1
                }
            }
        }
    }

    func setDNSServers(item: DNSMenuItem) {
        // Check if we have a load command to run
        if let loadCmd = item.setting.loadCmd {
            let command: [String] = loadCmd.componentsSeparatedByString(" ")
            let (result, output) = runCommand(command)
            if result != 0 {
                self.showAlert("Error", message: "Load command failed with exit code \(result): \(output)", style: NSAlertStyle.CriticalAlertStyle)
                return
            }
        }

        // Change the DNS settings
        let command: [String] = [ "networksetup", "-setdnsservers", self.config!.interface! ] + item.setting.servers!
        let (result, output) = runCommand(command)
        if result != 0 {
            self.showAlert("Error", message: "DNS change failed with exit code \(result): \(output)", style: NSAlertStyle.CriticalAlertStyle)
        }
        else {
            self.showAlert("DNS Changed", message: "Your DNS settings have been updated successfully.", style: NSAlertStyle.WarningAlertStyle)
        }
    }


    // MARK: - Dropdown menu

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
            item.setting = setting

            // Create the submenu
            let submenu = NSMenu()

            // Add a load button
            let loadItem = DNSMenuItem(title: "Load", action: #selector(AppDelegate.setDNSServers(_:)), keyEquivalent: "")
            loadItem.setting = setting
            submenu.addItem(loadItem)

            // Add a separator
            submenu.addItem(NSMenuItem.separatorItem())

            // Add the list of servers
            let serverTitleItem = NSMenuItem(title: "Servers:", action: nil, keyEquivalent: "")
            serverTitleItem.enabled = false
            submenu.addItem(serverTitleItem)
            for server in setting.servers! {
                let item = NSMenuItem(title: server, action: nil, keyEquivalent: "")
                item.indentationLevel = 1
                item.enabled = false
                submenu.addItem(item)
            }

            // Add the submenu to the menu item
            item.submenu = submenu

            // Add the menu item to the top of the menu
            self.menu.insertItem(item, atIndex: 0)
        }

        /* Highlight the enabled interface */
        self.highlightEnabledInterface()

        /* Fetch the current DNS settings and highlight the
         * selected setting in the menu if appropriate */
        self.highlightCurrentDNSServers()
    }

    func menuWillOpen(menu: NSMenu) {
        /* Only initialise the menu if the configuration has changed */
        if !self.checkForConfigUpdate() {
            /* In case the DNS servers have been changed, highlight the selected ones now */
            self.highlightCurrentDNSServers()
            return
        }

        /* Initialise the dropdown menu */
        self.initMenu()
    }


    // MARK: - Configuration file

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

    func saveLatestConfig() {
        if let data = self.config?.export() {
            do {
                try data.writeToFile(self.configFilePath, atomically: true, encoding: NSUTF8StringEncoding)
            }
            catch {
                print("Error saving configuration file")
            }
        }
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


    // MARK: - Actions

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


    // MARK: - Helpers

    func showAlert(title: String, message: String, style: NSAlertStyle) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButtonWithTitle("OK")
        alert.runModal()
    }

    func runCommand(args: [String]) -> (result: Int32, output: String) {
        let task = NSTask()
        task.launchPath = "/usr/bin/env"
        task.arguments = args
        let pipe = NSPipe()
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output: String = NSString(data: data, encoding: NSUTF8StringEncoding) as! String
        return (task.terminationStatus, output)
    }

}
