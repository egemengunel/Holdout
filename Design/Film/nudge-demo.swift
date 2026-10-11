// nudge-demo <command…>: drives a Nudge launched with `-NudgeDemoControl YES` (see
// TouchBarController.listenForDemoCommands): open, close, tab <0-3>, scroll start|end, pulse alert|cpu|off.
import Foundation
DistributedNotificationCenter.default().postNotificationName(
    .init("com.egemen.Nudge.demo"), object: CommandLine.arguments.dropFirst().joined(separator: " "), userInfo: nil, deliverImmediately: true)
