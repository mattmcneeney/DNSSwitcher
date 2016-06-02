//
//  SettingItem.swift
//  DNSSwitcher
//
//  Created by Matthew McNeeney on 02/06/2016.
//  Copyright © 2016 mattmc. All rights reserved.
//

import Cocoa
import SwiftyJSON

class SettingItem {

    var name: String?
    var servers: [String]?
    var interface: String?

    init(json: JSON) {
        self.name = json["name"].string
        self.servers = json["servers"].arrayValue.map({ $0.string! })
        self.interface = json["interface"].string
    }
    
}
