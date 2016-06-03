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
    var loadCmd: String?

    init(json: JSON) {
        self.name = json["name"].string
        self.servers = json["servers"].arrayValue.map({ $0.string! })
        self.loadCmd = json["load_cmd"].string
    }
    
}

extension SettingItem {

    func export() -> [String: AnyObject] {
        var data: [String: AnyObject] = [
            "name": self.name!,
            "servers": self.servers!
        ]
        if let loadCmd = self.loadCmd {
            data["load_cmd"] = loadCmd
        }
        return data
    }

}
