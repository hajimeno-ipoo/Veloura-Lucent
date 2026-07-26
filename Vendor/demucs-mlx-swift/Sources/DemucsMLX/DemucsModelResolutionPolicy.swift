/// Controls where Demucs model assets may be resolved from.
public enum DemucsModelResolutionPolicy: Sendable, Equatable {
    /// Preserve the upstream behavior: search known local locations first, then download from the Hub.
    case localThenHub

    /// Resolve only the exact directory supplied to `DemucsSeparator` as `modelDirectory`.
    ///
    /// This policy never searches environment variables, caches, the current working directory,
    /// or Hugging Face. It also ignores environment-requested post-load quantization so the
    /// validated local weights are executed unchanged. The directory must contain both files
    /// required by the selected model.
    case localOnly
}
