class ManageIQ::Providers::Azure::NumberOfVmsVisibilityService < ::NumberOfVmsVisibilityService
  def determine_visibility(number_of_vms, platform)
    @number_of_vms = number_of_vms

    hash = super

    # For Azure we will show two options in this case - private and public
    if @number_of_vms > 1
      hash[:hide].delete(:floating_ip_address)
    end

    hash
  end

  def number_of_vms
    @number_of_vms || 1
  end
end
