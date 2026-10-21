import CreateML
import Foundation
let args = CommandLine.arguments
let train = URL(fileURLWithPath: args[1]), test = URL(fileURLWithPath: args[2]), out = URL(fileURLWithPath: args[3])
var params = MLImageClassifier.ModelParameters()
params.maxIterations = Int(args[4]) ?? 25
params.augmentationOptions = [.crop, .blur, .exposure, .noise]
params.algorithm = .transferLearning(featureExtractor: .scenePrint(revision: 2), classifier: .logisticRegressor)
let model = try MLImageClassifier(trainingData: .labeledDirectories(at: train), parameters: params)
print("training accuracy", 1 - model.trainingMetrics.classificationError, "validation", 1 - model.validationMetrics.classificationError)
let ev = model.evaluation(on: .labeledDirectories(at: test))
print("REAL tiles accuracy", 1 - ev.classificationError)
try model.write(to: out)
