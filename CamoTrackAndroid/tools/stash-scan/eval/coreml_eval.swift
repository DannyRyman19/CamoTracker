import CoreML
import Foundation
import Vision
import ImageIO
// coreml_eval classify <model.mlmodelc> <dir of class folders> <out.json>
// coreml_eval detect <model.mlmodelc> <dir of images> <out.json>
let a = CommandLine.arguments
let config = MLModelConfiguration()
let model = try VNCoreMLModel(for: MLModel(contentsOf: URL(fileURLWithPath: a[2]), configuration: config))
func load(_ p: String) -> CGImage? {
    guard let s = CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(s, 0, nil)
}
var out: [String: Any] = [:]
let fm = FileManager.default
if a[1] == "classify" {
    var rows: [[String: Any]] = []
    for c in try fm.contentsOfDirectory(atPath: a[3]).sorted() {
        let dir = a[3] + "/" + c
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else { continue }
        for f in try fm.contentsOfDirectory(atPath: dir).sorted() where !f.hasPrefix(".") {
            guard let img = load(dir + "/" + f) else { continue }
            let r = VNCoreMLRequest(model: model); r.imageCropAndScaleOption = .scaleFill
            try VNImageRequestHandler(cgImage: img).perform([r])
            let res = (r.results as? [VNClassificationObservation]) ?? []
            rows.append(["truth": c, "file": f, "top": res.prefix(3).map { [$0.identifier, $0.confidence] as [Any] }])
        }
    }
    out["results"] = rows
} else {
    for f in try fm.contentsOfDirectory(atPath: a[3]).sorted() where f.hasSuffix(".jpg") || f.hasSuffix(".png") {
        guard let img = load(a[3] + "/" + f) else { continue }
        let r = VNCoreMLRequest(model: model); r.imageCropAndScaleOption = .scaleFill
        try VNImageRequestHandler(cgImage: img).perform([r])
        let W = Double(img.width), H = Double(img.height)
        out[f] = ((r.results as? [VNRecognizedObjectObservation]) ?? []).map { o -> [Double] in
            let b = o.boundingBox
            return [Double(b.minX) * W, (1 - Double(b.maxY)) * H, Double(b.width) * W, Double(b.height) * H, Double(o.confidence)]
        }
    }
}
try JSONSerialization.data(withJSONObject: out).write(to: URL(fileURLWithPath: a[4]))
print("ok")
