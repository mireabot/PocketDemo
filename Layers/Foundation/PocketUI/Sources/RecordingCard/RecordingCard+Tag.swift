public extension RecordingCard {
    struct Tag {
        public let title: String
        public let systemImage: String?

        public init(title: String, systemImage: String? = nil) {
            self.title = title
            self.systemImage = systemImage
        }
    }
}
