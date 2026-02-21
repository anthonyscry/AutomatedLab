function ConvertTo-DomainDN {
    <#
    .SYNOPSIS
        Converts a domain FQDN to distinguished name (DN) format.

    .DESCRIPTION
        Converts 'domain.tld' to 'DC=domain,DC=tld' format for use in
        Active Directory operations like New-GPLink -Target.

    .PARAMETER DomainFQDN
        The domain fully-qualified domain name (e.g., 'simplelab.local').

    .OUTPUTS
        String in distinguished name format (e.g., 'DC=simplelab,DC=local').
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$DomainFQDN
    )

    $parts = $DomainFQDN -split '\.'
    $dnParts = $parts | ForEach-Object { "DC=$_" }
    return $dnParts -join ','
}
