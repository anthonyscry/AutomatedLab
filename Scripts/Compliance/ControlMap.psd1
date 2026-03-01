@{
    Checks = @{
        'DNS.ExternalResolution' = @{
            Title = 'External DNS resolution check'
            Description = 'Verifies that external DNS resolution occurs only for approved hosts.'
            FrameworkMappings = @(
                @{
                    Framework = 'NIST.SP.800-53'
                    ControlId = 'SC-8'
                }
            )
        }
        'AD.DNS.ServiceRunning' = @{
            Title = 'AD DNS service status'
            Description = 'Confirms Active Directory DNS service is running on domain controllers.'
            FrameworkMappings = @(
                @{
                    Framework = 'NIST.SP.800-53'
                    ControlId = 'SI-10'
                }
            )
        }
    }
}
