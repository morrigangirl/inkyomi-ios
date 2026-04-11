import Foundation

/// Parses META-INF/encryption.xml to extract encrypted resource paths.
/// Uses Foundation's XMLParser instead of Android's XmlPullParser.
enum EncryptionXmlParser {

    /// Returns the set of relative paths that are encrypted in the EPUB.
    static func parse(_ data: Data) -> Set<String> {
        let delegate = EncryptionXmlDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.encryptedPaths
    }
}

private class EncryptionXmlDelegate: NSObject, XMLParserDelegate {
    var encryptedPaths = Set<String>()

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        // Look for <CipherReference URI="..."> elements
        let localName = elementName.components(separatedBy: ":").last ?? elementName
        if localName == "CipherReference", let uri = attributes["URI"] {
            encryptedPaths.insert(uri)
        }
    }
}
