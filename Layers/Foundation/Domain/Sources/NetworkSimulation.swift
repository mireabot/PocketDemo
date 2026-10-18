/// A fault the backend applies to one write, so a save can show a slow or lost reply on demand.
public enum NetworkSimulation: String, Sendable, CaseIterable {
    /// The server answers like an overloaded link: a late first byte, then the reply trickles in.
    case slow
    /// The server commits the write, then cuts the connection 1 second later without replying.
    /// The app keeps the write locally and resends it on the next refresh, not on its own.
    case lostReply = "drop"
    /// The connection fails before the request leaves the device, so the server never sees it.
    /// The app keeps the write locally and sends it on the next refresh, not on its own.
    case neverSent
}
