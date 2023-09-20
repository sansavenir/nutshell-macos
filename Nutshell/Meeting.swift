//
//  Meeting.swift
//  Nutshell
//
//  Created by Laurin Brandner on 15.06.23.
//

import Foundation

struct Meeting: Codable, Hashable, Comparable {
 
    var date: Date
    var title: String
    var text: [String]
    let id : UUID
    
    static func < (lhs: Self, rhs: Self) -> Bool {
        return lhs.date < rhs.date
    }
}
