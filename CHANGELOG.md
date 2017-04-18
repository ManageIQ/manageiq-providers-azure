# Change Log

All notable changes to this project will be documented in this file.

## Unreleased - as of Sprint 58 end 2017-04-10

### Added
- Add backtrace info to verify_credentials failure [(#43)](https://github.com/ManageIQ/manageiq-providers-azure/pull/43)

### Changed
- Update armrest version to 0.7.0 [(#42)](https://github.com/ManageIQ/manageiq-providers-azure/pull/42)

### Fixed
- Warn and bail on timeout when collecting metrics [(#44)](https://github.com/ManageIQ/manageiq-providers-azure/pull/44)

## Unreleased - as of Sprint 57 end 2017-03-27

### Added
- Move settings from ManageIQ main repo [(#40)](https://github.com/ManageIQ/manageiq-providers-azure/pull/40)

## Unreleased - as of Sprint 56 end 2017-03-13

### Added
- Azure deployment refresh enhancement [(#21)](https://github.com/ManageIQ/manageiq-providers-azure/pull/21)

## Unreleased - as of Sprint 55 end 2017-02-27

### Fixed
- Move require statement into the insights? method [(#38)](https://github.com/ManageIQ/manageiq-providers-azure/pull/38)
- Check for offer attribute when checking for Guest OS [(#37)](https://github.com/ManageIQ/manageiq-providers-azure/pull/37)
- Disable metrics and events in unsupported regions [(#36)](https://github.com/ManageIQ/manageiq-providers-azure/pull/36)

## Unreleased - as of Sprint 53 end 2017-01-30

### Added
- Return the Floating IPs available for reuse during instance provisioning [#25](https://github.com/ManageIQ/manageiq-providers-azure/pull/25)
- Support for US Government regions [#28](https://github.com/ManageIQ/manageiq-providers-azure/pull/28)

## Unreleased - as of Sprint 52 end 2017-01-14

### Added
- Associate a floating ip with its load balancer [#17](https://github.com/ManageIQ/manageiq-providers-azure/pull/17)

### Changed
- Delete all resources when deleting an Azure stack [#24](https://github.com/ManageIQ/manageiq-providers-azure/pull/24)
