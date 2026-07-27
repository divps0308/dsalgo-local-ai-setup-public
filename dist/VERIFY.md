# Release verification

Get-FileHash .\install.exe -Algorithm SHA256
Get-AuthenticodeSignature .\install.exe | Format-List *

This executable is signed with a self-signed certificate. Verify the certificate
thumbprint from the official GitHub repository before trusting it. Do not import
a downloaded certificate merely because it was downloaded. Installing the .cer
into Trusted Publishers or Trusted Root Certification Authorities is optional,
security-sensitive, and not recommended for ordinary public users.

Self-signing does not eliminate Unknown Publisher or SmartScreen warnings.
