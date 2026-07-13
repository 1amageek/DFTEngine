import CircuiteFoundation
import Foundation
import DFTCore

public protocol DFTEngineExecuting: Engine
where Request == DFTRequest, Output == DFTResult {}
