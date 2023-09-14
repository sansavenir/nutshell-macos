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
        if(!(segment.text.hasPrefix(" [") || segment.text.hasPrefix(" (") || segment.text.split(separator: " ").count < 5)){
            //            text.append(segment.text + " " + String(time+Double(segment.startTime)/Double(1000)) + "-" +  String(time+Double(segment.endTime)/Double(1000)) + "\n")
            //            text.append(segment.text + "\n")
            //            text[text.count-1] = text[text.count-1] + segment.text
            let interval = (time+Double(segment.startTime)/Double(1000)+0.3, time+Double(segment.endTime)/Double(1000)-0.3)
            let ind = findOverlap(interval: interval)
            print(interval)
            print(timestamps)
            
            if(ind.1 == -1){
                text.append(segment.text + "\n")
                timestamps.append(interval)
            } else {
                let subArray = Array(text[ind.0...ind.1])
                let combinedString = subArray.joined(separator: " ")
                
                let res = timestamps[ind.0].0 < interval.0 ? combineString(a: combinedString, b: segment.text) : combineString(a: segment.text, b: combinedString)
                
                text.removeSubrange(ind.0...ind.1)
                text.insert(res + "\n", at: ind.0)
                let intervalNew = (min(timestamps[ind.0].0, interval.0), max(timestamps[ind.1].1, interval.1))
                timestamps.removeSubrange(ind.0...ind.1)
                timestamps.insert(intervalNew, at: ind.0)
            }
            updateText?(text)
        }
    }
    
    func longestCommonSubsequence<T: Equatable>(_ array1: [T], _ array2: [T]) -> [T] {
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
        indicesA.reverse()
        indicesB.reverse()
        if(lcs.count > 4){
            return Array(array1[0...indicesA.last!] + array2[indicesB.last!...])
            
        } else {
            return array1 + array2
        }
    }
    
    func combineString(a: String, b: String) -> String {
        var a = a.split(separator: " ")
        if(a.count > 5){
            a.removeFirst()
            a.removeLast()
        }
        
        var b = b.split(separator: " ")
        if(b.count > 5){
            b.removeFirst()
            b.removeLast()
        }
        
        let res = longestCommonSubsequence(a, b)
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
