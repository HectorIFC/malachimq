# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Automated versioning system with SEMVER
- GitHub Actions for automatic release after merge to main
- Version bump script (`scripts/bump-version.sh`)
- Automatic changelog generation
- Versioned Docker tags
- Versioning documentation
- TLS/SSL support for TCP server (optional, configurable)
- Socket abstraction layer for transport-agnostic operations
- Development certificate generation script

### Changed
- **Docker**: Migrated from Alpine to Debian Bookworm slim base image
  - Switched from musl libc to glibc for better production stability
  - Improved compatibility with native extensions and NIFs
  - Added proper locale support (en_US.UTF-8)
  - Better debugging capabilities in production

### Security
- **CRITICAL**: Fixed cleartext transmission of credentials vulnerability
  - Added optional TLS encryption for TCP connections
  - Implemented strong cipher suites (TLS 1.2/1.3)
  - Created certificate-based authentication support
  - Backward compatible: TLS is optional (can be enabled via config)
- Fixed XSS vulnerability in dashboard queue name rendering
- Replaced weak SHA-256 password hashing with Argon2

### Changed
- BREAKING: Authentication now uses Argon2 instead of SHA-256
  - Existing password hashes will need to be regenerated
  - Update auth credentials in production after deployment

## [0.1.0] - 2025-12-22

### Added
- Initial implementation of MalachiMQ
- TCP messaging server
- Authentication system
- Web dashboard
- Multiple queue support
- ACK Manager for delivery guarantee
- Internationalization support (i18n)
- Docker and Docker Compose
- Initial documentation

[Unreleased]: https://github.com/HectorIFC/malachimq/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/HectorIFC/malachimq/releases/tag/v0.1.0
