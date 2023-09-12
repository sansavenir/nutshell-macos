//
//  Transcriber.swift
//  Nutshell
//
//  Created by Laurin Brandner on 02.06.23.
//

import Foundation
import AVFoundation
import ScreenCaptureKit
import Combine
import SwiftWhisper
import AudioKit


private let sampleRate = 16000

class Transcriber: NSObject, ObservableObject, SCStreamDelegate, SCStreamOutput {
    
    var recording = false
    
    var whisper = Whisper(fromFileURL: URL(fileURLWithPath: "/Users/jakubkotal/Downloads/ggml-base.en.bin"))
    //    var whisper = Whisper(fromFileURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin")!)
    

    @Published private(set) var transcript = [String]()
    
    private var audioEngine = AVAudioEngine()
    private var audioBuffer = [Float]()
    private var processingTimer: Timer?
    private var lastProcessed = 0
    private var fileNum = 1
    private var isRecording = true
    
    
    func updateAvailableContent() {
        Task {
            do {
//                self.availableContent = try await SCShareableContent.current
            }
            catch {
                print(error)
            }
//            assert(self.availableContent?.displays.isEmpty != nil, "There needs to be at least one display connected")
        }
    }
    
    func requestPermissions() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Nutshell needs permissions!"
            alert.informativeText = "Nutshell needs screen recording permissions, even if you only intend on recording audio."
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "No thanks, quit")
            alert.alertStyle = .informational
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            }
            NSApp.terminate(self)
        }
    }
    
    func startRecording() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in  // Move to a background thread
            self?.transcript = [""]
            let inputNode = self?.audioEngine.inputNode
            let inputFormat = inputNode?.outputFormat(forBus: 0)
            
            // Setup audio converter to convert to PCM with a single channel and sample rate of 44100
            let audioConverter = AVAudioConverter(from: inputFormat!, to: AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(sampleRate), channels: 1, interleaved: false)!)
            
            inputNode?.installTap(onBus: 0, bufferSize: 1600, format: inputFormat) { (buffer, when) in
                let pcmBuffer = AVAudioPCMBuffer(pcmFormat: AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(sampleRate), channels: 1, interleaved: false)!, frameCapacity: 1600)!
                
                let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
                    outStatus.pointee = AVAudioConverterInputStatus.haveData
                    return buffer
                }
                
                var error: NSError?
                audioConverter?.convert(to: pcmBuffer, error: &error, withInputFrom: inputBlock)
                
                if let channelData = pcmBuffer.floatChannelData?[0] {
                    self?.audioBuffer.append(contentsOf: Array(UnsafeBufferPointer(start: channelData, count: Int(pcmBuffer.frameLength))))
                }
            }
            
            do {
                try self?.audioEngine.start()
            } catch {
                print("Could not start audio engine: \(error)")
            }
        }
        
        Task { [weak self] in // Moved to a Task to run the asynchronous function
            do {
                try await self?.process()
            } catch {
                print("An error occurred while processing: \(error)")
            }
        }
    
    }

    
    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        // Invalidate the timer
        processingTimer?.invalidate()
        processingTimer = nil
        self.isRecording = false
        // Now audioBuffer contains the float samples.
        // You can save it to memory or process it.
    }
    
    private func saveToWavFile(file: [Float]) {
        // Create AVAudioFormat
        let audioFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(sampleRate), channels: 1, interleaved: false)!
        
        // Create AVAudioPCMBuffer
        let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: AVAudioFrameCount(file.count))!
        pcmBuffer.frameLength = AVAudioFrameCount(file.count)
        
        // Copy data to pcmBuffer
        let channelData = pcmBuffer.floatChannelData![0]
        for i in 0..<file.count {
            channelData[i] = file[i]
        }
        
        let outputFileUrl = URL(fileURLWithPath: "/Users/jakubkotal/Downloads/rec/test\(self.fileNum).wav")
        self.fileNum  += 1
        
        do {
            let audioFile = try AVAudioFile(forWriting: outputFileUrl, settings: audioFormat.settings)
            try audioFile.write(from: pcmBuffer)
            print("Successfully saved to \(outputFileUrl)")
        } catch {
            print("Error while saving to wav file: \(error)")
        }
    }
    
    private func process() async{
        while(self.isRecording){
            if(self.audioBuffer.count > 1000){
                let temp = self.audioBuffer
                self.audioBuffer = []
                saveToWavFile(file: temp)
                let text = try! await whisper.transcribe(audioFrames: temp)
                print("Transcribed audio:", text.map(\.text).joined())
                //                    self.transcript.append(text.map(\.text).joined())
                self.transcript[self.transcript.count-1].append(text.map(\.text).joined())
            }
        }
    }

}
//
