import Foundation
import RegexBuilder

let text = "remember: hello"
let regex = try Regex("remember:")
if text.contains(regex) {
    print("Match found")
} else {
    print("No match")
}
