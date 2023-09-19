//
//  WhisperHandler.swift
//  Nutshell
//
//  Created by jakub kotal on 13.09.23.
//

import SwiftWhisper
import Foundation

class WhisperHandler: WhisperDelegate {
    var onNewSegmentsReceived: (([Segment]) -> Void)?
    var updateText: (([String]) -> Void)?
    var time = 0.0
    var text = [""]
    var timestamps = [(0.0, 0.0)]
    func whisper(_ aWhisper: Whisper, didProcessNewSegments segments: [Segment], atIndex index: Int) {
        print("New Segments at index \(index): \(segments)")
        // Append or insert new text into the UI
        let segment = segments[0]
        if(!(segment.text.hasPrefix(" [") || segment.text.hasPrefix(" (") || segment.text.split(separator: " ").count < 4)){
            let interval = (time+Double(segment.startTime)/Double(1000)+0.1, time+Double(segment.endTime)/Double(1000)-0.1)
//            let ind = findOverlap(interval: interval)
            let ind = timestamps.last!

            if(ind.1 < interval.0){
                text.append(segment.text)
                timestamps.append(interval)
            } else if(ind.0 < interval.0 && interval.0 < ind.1){
                let res = combineString(a: text.last!, b: segment.text, interval: interval)
                text.removeLast()
                text.append(res)
            }
            updateText?(text)
        }
    }
    
    func longestCommonSubsequence<T: Equatable>(_ array1: [T], _ array2: [T], interval: (Double, Double)) -> [T] {
        let m = array1.count
        let n = array2.count
        
        // Initialize a 2D array to store lengths of LCS solutions for subproblems
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        
        // Build the dp matrix
        for i in 1...m {
            for j in 1...n {
                if array1[i - 1] == array2[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }
        
        // Reconstruct the longest common subsequence
        var lcs: [T] = []
        var i = m
        var j = n
        var indicesA: [Int] = []
        var indicesB: [Int] = []
        while i > 0 && j > 0 {
            if array1[i - 1] == array2[j - 1] {
                lcs.insert(array1[i - 1], at: 0)
                indicesA.append(i - 1)
                indicesB.append(j - 1)
                i -= 1
                j -= 1
            } else if dp[i - 1][j] > dp[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }
        
        if(lcs.count > 1){
            let ind = timestamps.last!
            let intervalNew = (min(ind.0, interval.0), max(ind.1, interval.1))
            timestamps.removeLast()
            timestamps.append(intervalNew)
            return Array(array1[0...indicesA.first!-1] + array2[indicesB.first!...])
        } else {
            timestamps.append(interval)
            return array1 + array2
        }
    }

    
    func findLongestCommonSuffixPrefix<T: Equatable>(a: [T], b: [T]) -> [T] {
        var longest: [T] = []
        let minCount = min(a.count, b.count)
        
        for i in 1...minCount {
            let suffixA = Array(a.suffix(i))
            let prefixB = Array(b.prefix(i))
            
            if suffixA == prefixB {
                longest = suffixA
            }
        }
        
        if(longest.count == 0){
            return Array(a+b)
        } else {
            return Array(a[0...a.count-longest.count-1] + b[longest.count...])
        }
    }
    
    func combineString(a: String, b: String, interval: (Double, Double)) -> String {
        let a = a.split(separator: " ")
        let b = b.split(separator: " ")
//        a.removeLast()
//        a.removeLast()
//        b.removeFirst()
//        b.removeFirst()
//        let res = findLongestCommonSuffixPrefix(a: a, b: b)
        
        let len = min(a.count, min(b.count, 7))
        let res = Array(a.prefix(a.count-len)) + longestCommonSubsequence(Array(a.suffix(len)), Array(b.prefix(len)), interval: interval) + Array(b.suffix(b.count-len))
        
        return res.joined(separator: " ")
    }
    
    func findOverlap(interval: (Double, Double)) -> (Int, Int) {
        var a = -1
        var b = 0
        for i in stride(from: timestamps.count - 1, through: 0, by: -1) {
            if(a == -1 && intervalsOverlap(a: interval, b: timestamps[i])){
                a = i
            }
            if(a != -1 && !intervalsOverlap(a: interval, b: timestamps[i])){
                b = i+1
                break
            }
        }
        func intervalsOverlap(a: (Double, Double), b: (Double, Double)) -> Bool {
            return a.0 < b.1 && a.1 > b.0
        }
        return (b,a)
    }
}
