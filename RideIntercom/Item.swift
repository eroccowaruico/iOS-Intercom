//
//  Item.swift
//  RideIntercom
//
//  Created by Naohito Sasao on 2026/04/18.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
