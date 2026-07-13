import CircuiteFoundation
import Foundation
import DFTCore
import XcircuitePackage

public protocol DFTEngineExecuting: Engine
where Request == DFTRequest, Output == XcircuiteEngineResultEnvelope<DFTPayload> {}
