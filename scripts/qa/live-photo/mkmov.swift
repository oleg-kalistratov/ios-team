import Foundation
import AVFoundation

let a = CommandLine.arguments
let inURL = URL(fileURLWithPath: a[1]), outURL = URL(fileURLWithPath: a[2]), uuid = a[3]
try? FileManager.default.removeItem(at: outURL)
let asset = AVURLAsset(url: inURL)
let sem = DispatchSemaphore(value: 0)
Task {
    do {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { exit(1) }
        let reader = try AVAssetReader(asset: asset)
        let rout = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(rout)
        let writer = try AVAssetWriter(outputURL: outURL, fileType: .mov)
        let fmt = try await track.load(.formatDescriptions).first
        let vin = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: fmt)
        vin.transform = try await track.load(.preferredTransform)
        writer.add(vin)
        let idItem = AVMutableMetadataItem()
        idItem.key = AVMetadataKey.quickTimeMetadataKeyContentIdentifier as NSString
        idItem.keySpace = .quickTimeMetadata
        idItem.value = uuid as NSString
        idItem.dataType = "com.apple.metadata.datatype.UTF-8"
        writer.metadata = [idItem]
        let spec: [String: Any] = [
            kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String: "mdta/com.apple.quicktime.still-image-time",
            kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String: "com.apple.metadata.datatype.int8"
        ]
        var md: CMFormatDescription?
        CMMetadataFormatDescriptionCreateWithMetadataSpecifications(allocator: kCFAllocatorDefault, metadataType: kCMMetadataFormatType_Boxed, metadataSpecifications: [spec] as CFArray, formatDescriptionOut: &md)
        let min = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: md)
        let adaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: min)
        writer.add(min)
        reader.startReading(); writer.startWriting(); writer.startSession(atSourceTime: .zero)
        let still = AVMutableMetadataItem()
        still.key = "com.apple.quicktime.still-image-time" as NSString
        still.keySpace = .quickTimeMetadata
        still.value = 0 as NSNumber
        still.dataType = "com.apple.metadata.datatype.int8"
        adaptor.append(AVTimedMetadataGroup(items: [still], timeRange: CMTimeRange(start: CMTime(value: 15, timescale: 30), duration: CMTime(value: 1, timescale: 30))))
        min.markAsFinished()
        while let sb = rout.copyNextSampleBuffer() {
            while !vin.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.01) }
            vin.append(sb)
        }
        vin.markAsFinished()
        await writer.finishWriting()
        print("status", writer.status.rawValue, writer.error as Any)
    } catch { print("err", error) }
    sem.signal()
}
sem.wait()
