// AeroSpace-edge deliberately uses its own app id, app name and CLI name so that it installs and runs
// side by side with an upstream AeroSpace install: separate app bundle, separate Spotlight entry,
// separate Accessibility grant, separate socket, separate LaunchAgent.
// Upstream's values are `bobko.aerospace` / `AeroSpace` / `aerospace` — never reintroduce them here.
public let stableAeroSpaceAppId: String = "vitorebatista.aerospace-edge"
public let aeroSpaceCliName: String = "aerospace-edge"
#if DEBUG
    public let aeroSpaceAppId: String = "vitorebatista.aerospace-edge.debug"
    public let aeroSpaceAppName: String = "AeroSpace-edge-Debug"
#else
    public let aeroSpaceAppId: String = stableAeroSpaceAppId
    public let aeroSpaceAppName: String = "AeroSpace-edge"
#endif
