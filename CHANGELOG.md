# Change Log

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)

## Unreleased - as of Sprint 67 ending 2017-08-21

### Fixed
- Updated metric names for Azure metrics [(#114)](https://github.com/ManageIQ/manageiq-providers-azure/pull/114)

### Added
- Create resource group association for instances and managed images [(#72)](https://github.com/ManageIQ/manageiq-providers-azure/pull/72)

## Unreleased - as of Sprint 66 ending 2017-08-07

### Added
- Refactor discovery code eliminate a warning [(#104)](https://github.com/ManageIQ/manageiq-providers-azure/pull/104)
- Add additional_regions support and add specs for regions [(#103)](https://github.com/ManageIQ/manageiq-providers-azure/pull/103)

### Fixed
- Remove sample orchestration template [(#107)](https://github.com/ManageIQ/manageiq-providers-azure/pull/107)
- Ignore case when gathering data for region  [(#99)](https://github.com/ManageIQ/manageiq-providers-azure/pull/99)

## Unreleased - as of Sprint 65 ending 2017-07-24

### Added
- Marketplace image support [(#95)](https://github.com/ManageIQ/manageiq-providers-azure/pull/95)
- Add blacklists for VM username and password when provisioning [(#88)](https://github.com/ManageIQ/manageiq-providers-azure/pull/88)

### Fixed
- Fix find_destination_in_vmdb to use insensitive find azure machine name in vmdb [(#93)](https://github.com/ManageIQ/manageiq-providers-azure/pull/93)

## Unreleased - as of Sprint 64 ending 2017-07-10

### Added
- Disable reset operation for VMs and add specs [(#81)](https://github.com/ManageIQ/manageiq-providers-azure/pull/81)
- Use a simpler name for network ports [(#80)](https://github.com/ManageIQ/manageiq-providers-azure/pull/80)
- Decrypt client keys in raw connect [(#86)](https://github.com/ManageIQ/manageiq-providers-azure/pull/86)

### Fixed
- Security Groups array_integer data type [(#91)](https://github.com/ManageIQ/manageiq-providers-azure/pull/91)
- Fix VM password restrictions [(#87)](https://github.com/ManageIQ/manageiq-providers-azure/pull/87)

## Unreleased - as of Sprint 61 ending 2017-05-22

### Fixed
- Provisioning - First and Last names are not required. [(#73)](https://github.com/ManageIQ/manageiq-providers-azure/pull/73)

## Unreleased - as of Sprint 60 ending 2017-05-08

### Added
- Make azure-armrest dependency less pessimistic [(#55)](https://github.com/ManageIQ/manageiq-providers-azure/pull/55)

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
