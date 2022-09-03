function Get-Web-JSON( $URL ){

    ConvertFrom-Json (Invoke-WebRequest $URL)

}
function Dll-Loader( $Path ){

    Unblock-File -Path $Path
    Import-Module $Path

}

Add-Type -AssemblyName System.IO.Compression.FileSystem

Dll-Loader( "$PSScriptRoot\dependencies\nuget.frameworks\NuGet.Frameworks.dll" )
Dll-Loader( "$PSScriptRoot\dependencies\semver\Semver.dll" )

function Get-NuGet-Dlls {
    
    Param(
        [Parameter(Mandatory=$true,
        ValueFromPipeline=$true)]
        [string]
        $PackageName,
        [string] $Path,

        [string] $Range, #version range
        [string[]] $Group = @(), #dependency grouping. used mainly for packages that have multiple .net versions

        [switch] $y, #use the latest stable release for all packages
        [switch] $n #use the latest stable release for all packages
    )

    $Exclude = New-Object System.Collections.Generic.List[System.Object]

    function Ver-Parse( $Version ){
        
        if( ($Version -split "\.").Count -gt 3 ){
        
            $s = $Version -split "\."
            $Version = @(
                ( $s[0..2] -join "." ),
                ( $s[3..$s.Length] -join "." )
            ) -join "-"
        
        }
        [Semver.SemVersion]::Parse( $Version )
        
    }
    function Ver-Compare{

        Param(
            [Parameter(Mandatory=$true,
            ValueFromPipeline=$true)]
            [Semver.SemVersion] $A,
            [Parameter(Mandatory=$true)]
            [Semver.SemVersion] $B
        )
        [Semver.SemVersion]::Compare( $A, $B )

    }
    function Ver-InRange{

        Param(
            [Parameter(Mandatory=$true,
            ValueFromPipeline=$true)]
            [Semver.SemVersion] $A,
            [Parameter(Mandatory=$true)]
            [System.Object[]] $R
        )

        $LowLimit = ( ( Ver-Compare -A $A -B $R.Lower ) -ge 0 )
        $TopLimit = $True

        if( $R.Upper ){
            $TopLimit = ( ( Ver-Compare -A $A -B $R.Upper ) -le 0 )
        }

        $LowLimit -and $TopLimit

    }

    function API{
    
        Param(
            [Parameter(Mandatory=$true,
            ValueFromPipeline=$true)]
            [string]
            $PackageName,

            [string] $Range, #version range
            [string[]] $Group = @(), #dependency grouping. used mainly for packages that have multiple .net versions

            [switch] $y, #use the latest stable release for all packages
            [switch] $n #do not traverse dependencies
        )

        #optimizes performance by exclusion of packages
            #this is mainly used when a dependent package references the same dependency 2+ times

        $Output = New-Object 'System.Collections.Generic.List[System.Object]'

        if( $Exclude.indexOf( $PackageName ) -ne -1 ){
            $Output.Add( @{ "name" = $PackageName } )
            return $Output
        }

        $TopParent = $False
        if( $Exclude.Count -eq 0 ){ $TopParent = $True }

        $Exclude.Add($PackageName)

        if( $Range ){

            $s = ($Range -split ",").Trim()
                $s[0] = $s[0] -replace "^.", ""
                $s[1] = $s[1] -replace ".$", ""
            $s = $s.Trim()
    
            $Bounds = @{ "Lower" = Ver-Parse( $s[0] )}

            if( $s[1] ){ $Bounds.Upper = Ver-Parse( $s[1] ) }

        }

        $Registry = Get-Web-JSON (@(
                "https://api.nuget.org/v3/registration5-gz-semver2",
                $PackageName,
                "index.json"
            ) -join "/")

        $Packages = [ordered]@{}
        $i = @{}

        for(
            $i.reg = 0;
            $i.reg -lt $Registry.items.count;
            $i.reg++
        ){

            $Registration = $Registry.items[ $i.reg ]

            if( $Range ){

                $states = foreach( $row in ([ordered]@{
                    "Lower" = Ver-Parse( $Registration.lower )
                    "Upper" = Ver-Parse( $Registration.upper )
                }).GetEnumerator()){
        
                    @( Ver-Compare -A $Bounds.Lower -B $row.value )
                    if( $Bounds.Upper ){

                        @( Ver-Compare -A $Bounds.Upper -B $row.value )

                    } else {

                        @( 1 )

                    }
        
                }

                $isInRange = ( -not( ( $states | Measure-Object -Sum ) -eq 4 ) ) -or ( -not( ( $states | Measure-Object -Sum ) -eq -4 ) )

            } else { $isInRange = $true }

            if( $isInRange ){

                #if $states evals to @(-1,-1,-1,-1) or @(1,1,1,1)
                #  that means that there is no overlap betweeen the ranges
                #  1,1,1,1 means that the requested bounds are higher
                #    than the downloaded ones
                #  -1,-1,-1,-1 means the opposite
                #
                #  a little too much complex math, I know...
                #  sorry, future me

                for(
                    $i.packs=0;
                    $i.packs -lt $Registration.items.count;
                    $i.packs++
                ){
            
                    $CatalogEntry = $Registration.items[ $i.packs ].catalogEntry

                    $Package = @{
                
                        "Version" = Ver-Parse( $CatalogEntry.version );
                        "URL" = @{
                    
                            "API" = $CatalogEntry.'@id';
                            "download" = $CatalogEntry.packageContent

                        }
                
                    }

                    if( $Range ){

                        if( Ver-InRange -A ($Package.Version) -R $Bounds ){
                
                            $Packages[ $Package.Version ] = $Package
                
                        }
                
                    } else { $Packages[ $Package.Version ] = $Package }

                }
        
            }
        
        }

        $sel = @{}

        while( @($Packages.Keys).IndexOf( $sel.package ) -eq -1 ){
    
            if( -not($y) ){

                Clear-Host
                Write-Host "Select one of the following versions ($PackageName):"
                Write-Host "================ Versions: ================"

            }
        
            $Defaults = @()

            foreach( $row in $Packages.GetEnumerator() ){
        
                if( -not($y) ){ Write-Host $row.name }

                if( $row.Value.Version.IsRelease ){ $Defaults += $row.Name }
                $Last = $row.Name
        
            }

            if( -not( $Defaults[0] )){ $Defaults += $Last }
            if( -not($y) ){

                $sel.package = Read-Host ("which version? (default=" + $Defaults[-1] + ")")

            }

            if( -not( $sel.package ) ){ $sel.package = $defaults[-1] }
    
        }

        $Choice = $Packages[ $sel.package ]

        $Details = Get-Web-JSON $Choice.URL.API

        $Choice.Frameworks = $Details.dependencyGroups.forEach({
    
            @{ $_.targetFramework = $_.dependencies }
    
        })

        $Preselected = @()
        $Preselected += $Group | Where { $Choice.Frameworks.Keys -contains $_ }

        if( ( $Preselected.Count -eq 0 ) -or -not ( $y ) ){
    
            while( $Choice.Frameworks.Keys.IndexOf( $sel.framework ) -eq -1 ){

                Clear-Host
                Write-Host "Select one of the following frameworks: ($PackageName)"
                Write-Host "================ groups: ================"

                $Choice.Frameworks.Keys.forEach({ Write-Host $_ })

                $Prompt = "which group?"

                if( -not( $y ) -and $Preselected.Count -ne 0 ){
            
                    $Prompt += " (default=$( $Preselected[-1] ))"
                    $default = $Preselected[-1]
            
                }

                $sel.framework = Read-Host $Prompt

                if( -not( $sel.framework ) ){ $sel.framework = $default }
        
            }

            $Group += $sel.framework; $Preselected += $sel.framework

        }

        $temp = @{}
        $Choice.Frameworks | % { $temp += $_ }
        $Choice.Frameworks = $temp

        $Output.Add( @{ "name" = $PackageName; "dl" = $Choice.URL.download; "v" = $Choice.Version.toString(); "framework" = $Preselected[-1] } )

        if( $n ){ return $Output }

        $Choice.Frameworks[ $Preselected[-1] ].forEach({

            $Request = @{

                "PackageName" = $_.id.ToLower();
                "Range" = $_.range;
                "Group" = $Group;
                "y" = $y;
        
            }

            $SubOut = API @Request

            if( $SubOut ){
        
                if( $SubOut.toString() -eq "System.Collections.Hashtable" ){
            
                    $Output.Add( $SubOut )
            
                } else { $Output.AddRange( $SubOut ) }
        
            }

        })

        $Output

    }

    $Request = @{
        "PackageName" = $PackageName.ToLower();
    }
    
    if( $Range ){ $Request.Range = $Range }
    if( $Group ){ $Request.Group = $Group }
    if( $y ){ $Request.y = $y }
    if( $n ){ $Request.n = $n }

    $Response = @{}

    $Response.PackageList = API @Request

    if( $Path ){

        $Response.PackageList.forEach({

            if( $_.dl ){

                $OutDir = "$Path\$($_.name)"

                if( -not( Test-Path $OutDir ) ){ $null = mkdir -p $OutDir }

                Invoke-WebRequest -URI $_.dl -OutFile "$Path\temp.zip"
                
                $Unzipper = [System.IO.Compression.ZipFile]
                $UnzipperExt = [System.IO.Compression.ZipFileExtensions]

                $NugetFramework = [NuGet.Frameworks.NuGetFramework]

                $Zip = $Unzipper::OpenRead( "$Path\temp.zip" )

                $Foldername = $NugetFramework::Parse( $_.framework ).GetShortFolderName()

                $OutFiles = @()

                $Zip.Entries | Where { 
                        
                        ( $_.FullName -like "lib/$Foldername*" ) -and ( $_.Name -like "*.dll" ) 
                        
                    } | ForEach { 
                    
                        $UnzipperExt::ExtractToFile( $_, "$OutDir\$($_.Name)", $true )
                        $OutFiles += "$OutDir\$($_.Name)"
                    
                    }

                $_.outfiles = $OutFiles

                $Zip.Dispose()

                Remove-Item -Path "$Path\temp.zip"

            }

        })

    }

    $Response.PackageList

}

