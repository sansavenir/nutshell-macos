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
    
    private var whisperHandler: WhisperHandler?
    private var whisper: Whisper?
    //    var whisper = Whisper(fromFileURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin")!)
//    var whisperHandler = WhisperHandler()
//    var whisper.delegate = whisperHandler
    

    @Published private(set) var transcript = [String]()
    
    private var audioEngine = AVAudioEngine()
    private var audioBuffer = [Float]()
    private var lhs = [Float]()
    private var processingTimer: Timer?
    private var lastProcessed = 0
    private var fileNum = 1
    private var isRecording = true
    private var currentPos = 0
    
    override init (){
        super.init()
        whisper = Whisper(fromFileURL: URL(fileURLWithPath: "/Users/jakubkotal/Downloads/ggml-tiny.en.bin"))
        whisperHandler = WhisperHandler()
        whisper?.delegate = whisperHandler
        
        whisperHandler?.updateText = { [weak self] text in
            DispatchQueue.main.async {
                self?.transcript = text
            }
        }
    }
    
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
        self.isRecording = true
        
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
        self.isRecording = false
        self.transcript = [""]
        self.whisperHandler?.text = [""]
        self.currentPos = 0
        self.audioBuffer = []
        self.whisperHandler?.timestamps = [(0.0,0.0)]
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
        // Use a DispatchGroup to wait for all async tasks to complete
        let group = DispatchGroup()

        while self.isRecording {
            let sec = 7
            if self.audioBuffer.count > sec*sampleRate {
                // Copy the buffer and clear it

                // Async task
                group.enter()
                self.currentPos += self.audioBuffer.count-(sec*sampleRate)
                self.audioBuffer = Array(self.audioBuffer[self.audioBuffer.count-(sec*sampleRate)..<self.audioBuffer.count])
                self.whisperHandler?.time = Double(self.currentPos)/Double(sampleRate)
                _ = try! await self.whisper!.transcribe(audioFrames: self.audioBuffer)
                
                
//                DispatchQueue.global().async {
//                    Task.init {
//                        do {
//                            _ = try await self.whisper!.transcribe(audioFrames: self.audioBuffer)
//                            // Save the last 8000 elements for the next iteration
////                            self.lhs = temp.suffix(1000)
//
//                        } catch {
//                            print("Error during transcription: \(error)")
//                        }
//                        group.leave()
//                    }
//                }
//
//                // Optionally, you can wait for all transcriptions to complete before exiting
//                group.wait()
//                self.currentPos += temp.count
            }
        }
    }


}
