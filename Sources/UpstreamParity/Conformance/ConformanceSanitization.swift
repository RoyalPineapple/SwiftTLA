func redactingSecrets(in value: String) -> String {
  let URLRedacted = value.replacing(#/(https?:\/\/)[^\/@\s]+@/#) {
    "\($0.output.1)<redacted>@"
  }
  return URLRedacted.replacing(
    #/(?im)\b([A-Z][A-Z0-9_]*(?:TOKEN|SECRET|PASSWORD|API_KEY)|TOKEN|SECRET|PASSWORD|API_KEY)\s*[:=]\s*\S+/#
  ) {
    "\($0.output.1)=<redacted>"
  }
}
