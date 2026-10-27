import CreateML
import Foundation
// train_grid <train dir with annotations.json> <validation dir> <out.mlmodel> [iterations]
let args = CommandLine.arguments
let train = MLObjectDetector.DataSource.directoryWithImagesAndJsonAnnotation(at: URL(fileURLWithPath: args[1]))
let check = MLObjectDetector.DataSource.directoryWithImagesAndJsonAnnotation(at: URL(fileURLWithPath: args[2]))
let params = MLObjectDetector.ModelParameters(validation: .dataSource(check), batchSize: 16,
                                              maxIterations: Int(args.count > 4 ? args[4] : "") ?? 1500,
                                              algorithm: .transferLearning(.objectPrint(revision: 1)))
let model = try MLObjectDetector(trainingData: train, parameters: params, annotationType: .boundingBox(units: .pixel, origin: .topLeft, anchor: .center))
print("training mAP", model.trainingMetrics.meanAveragePrecision)
print("validation mAP", model.validationMetrics.meanAveragePrecision)
try model.write(to: URL(fileURLWithPath: args[3]))
