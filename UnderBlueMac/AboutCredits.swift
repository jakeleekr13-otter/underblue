import AppKit

/// The credits line of the About panel. The version and the icon come from the app itself.
enum AboutCredits {
    static var text: NSAttributedString {
        let body = NSMutableAttributedString(
            string: "Restores colour and clarity in underwater photos and videos. Everything is processed on this Mac.\n\n"
                + "Includes Depth Anything V2 Small (Core ML) by Lihe Yang et al., converted by Apple, under the Apache License 2.0. "
                + "The full license is in Help ▸ Open-source licenses.\n\n",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor])
        for (title, address) in [("Support", "https://jakeleekr13-otter.github.io/underblue-support/support/"),
                                 ("Privacy policy", "https://jakeleekr13-otter.github.io/underblue-support/privacy/")] {
            body.append(NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 11), .link: URL(string: address)!]))
            if title == "Support" { body.append(NSAttributedString(string: "   ")) }
        }
        return body
    }
}
