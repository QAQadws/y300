/// Opt-in look-ahead policy. Other HTML consumers retain disk-only scheduling.
final class ForumHtmlImagePredecodePolicy {
  const ForumHtmlImagePredecodePolicy({
    required this.maxDecodedBytesPerImage,
    this.forwardImageCount = 2,
    this.backwardImageCount = 1,
    this.decodeExtentFactor = 1,
    this.forwardDiskExtentFactor = 2,
    this.backwardDiskExtentFactor = 1,
  });

  final int maxDecodedBytesPerImage;
  final int forwardImageCount;
  final int backwardImageCount;
  final double decodeExtentFactor;
  final double forwardDiskExtentFactor;
  final double backwardDiskExtentFactor;
}
