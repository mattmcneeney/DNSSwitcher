//
//  Config.swift
//  DNSSwitcher
//
//  Created by Matthew McNeeney on 02/06/2016.
//  Copyright © 2016 mattmc. All rights reserved.
//

import Cocoa
import SwiftyJSON

class Config {

    var settings: [SettingItem]?

    init(data: NSData) {
        self.settings = []
        let json = JSON(data: data)
        guard let settings = json["settings"].array else {
            // No servers found
            print("No configuration settings found")
            return
        }
        for setting in settings {
            let settingItem = SettingItem(json: setting)
            if settingItem.name == nil || settingItem.servers == nil || settingItem.interface == nil {
                print("Error parsing server item: \(settingItem.name)")
                continue
            }
            self.settings?.append(settingItem)
        }
    }

}
