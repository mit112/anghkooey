import FoundationModels

@Generable
public struct ClozeResponse: Codable {
    public var items: [ClozeDraft]
}
