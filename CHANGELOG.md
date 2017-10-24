# Change Log

All notable changes to this project will be documented in this file.

## Fine-4

### Added
- SSA Support for Managed Images [(#133)](https://github.com/ManageIQ/manageiq-providers-azure/pull/133)
- Changes to wait for snapshot completion. [(#126)](https://github.com/ManageIQ/manageiq-providers-azure/pull/126)
- Ignore case when gathering data for region [(#99)](https://github.com/ManageIQ/manageiq-providers-azure/pull/99)
- Updated metric names for Azure metrics [(#114)](https://github.com/ManageIQ/manageiq-providers-azure/pull/114)
- Add Snapshot Code for Azure Managed Disks [(#117)](https://github.com/ManageIQ/manageiq-providers-azure/pull/117)
- Snapshot Blob Disks for SSA [(#122)](https://github.com/ManageIQ/manageiq-providers-azure/pull/122)
- Wait for SSA Snapshot Success [(#125)](https://github.com/ManageIQ/manageiq-providers-azure/pull/125)

## Fine-3

### Added
- Refactor service creation lock down api-version strings [(#51)](https://github.com/ManageIQ/manageiq-providers-azure/pull/51)
- Add support for managed images [(#65)](https://github.com/ManageIQ/manageiq-providers-azure/pull/65)

### Fixed
- Upgrade armrest gem to 0.7.3 [(#74)](https://github.com/ManageIQ/manageiq-providers-azure/pull/74)
- Handle possibility of network_port not having private_ip_address [(#85)](https://github.com/ManageIQ/manageiq-providers-azure/pull/85)
- Handle possibility of no orchestration stacks [(#84)](https://github.com/ManageIQ/manageiq-providers-azure/pull/84)

## Fine-1

### Added
- Add backtrace info to verify_credentials failure [(#43)](https://github.com/ManageIQ/manageiq-providers-azure/pull/43)
- Move settings from ManageIQ main repo [(#40)](https://github.com/ManageIQ/manageiq-providers-azure/pull/40)
- Azure deployment refresh enhancement [(#21)](https://github.com/ManageIQ/manageiq-providers-azure/pull/21)
- Associate a floating ip with its load balancer [#17](https://github.com/ManageIQ/manageiq-providers-azure/pull/17)
- Return the Floating IPs available for reuse during instance provisioning [#25](https://github.com/ManageIQ/manageiq-providers-azure/pull/25)
- Support for US Government regions [#28](https://github.com/ManageIQ/manageiq-providers-azure/pull/28)

### Changed
- Update armrest version to 0.7.0 [(#42)](https://github.com/ManageIQ/manageiq-providers-azure/pull/42)
- Delete all resources when deleting an Azure stack [#24](https://github.com/ManageIQ/manageiq-providers-azure/pull/24)

### Fixed
- Ensure managers change zone and provider region with CloudManager [(#47)](https://github.com/ManageIQ/manageiq-providers-azure/pull/47)
- Warn and bail on timeout when collecting metrics [(#44)](https://github.com/ManageIQ/manageiq-providers-azure/pull/44)
- Move require statement into the insights? method [(#38)](https://github.com/ManageIQ/manageiq-providers-azure/pull/38)
- Check for offer attribute when checking for Guest OS [(#37)](https://github.com/ManageIQ/manageiq-providers-azure/pull/37)
- Disable metrics and events in unsupported regions [(#36)](https://github.com/ManageIQ/manageiq-providers-azure/pull/36)
