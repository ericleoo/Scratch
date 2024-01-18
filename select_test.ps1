<#
.DESCRIPTION
    This script provides a set of functions to interactively select the Cardlink version, test
    cases, payment network, card, and merchant for executing Robot tests. The relevant variables
    are then added before starting the Robot test execution.
.PARAMETER testPath
    The path to the folder containing Robot test files.
#>
param (
    [Parameter(Mandatory = $true)]
    [string]$testPath
)

<#
.SYNOPSIS
    Adds a dependency's directory to the system PATH environment variable if it is not already 
    present.

.DESCRIPTION
    This function adds directory of the specified dependency to the system PATH environment variable
    if it does not already exist in the PATH. This is useful for ensuring that required dependencies
    are available for execution.

.PARAMETER dependency
    The name of the dependency to be added to the PATH.

.EXAMPLE
    Add-PathVariable "wc3270"
    # Adds "dependencies\wc3270" directory to the system PATH if not already present.
#>
function Add-PathVariable {
    param ([string]$dependency)

    if (!(Get-Command $dependency -ErrorAction SilentlyContinue)) {
        $dependencyDirectory = (Resolve-Path -LiteralPath ("dependencies\" + $dependency)).Path
        if ($env:Path -notlike ("*" + $dependencyDirectory + "*")) {
            $env:Path += ";" + $dependencyDirectory
        }
    }
}

<#
.SYNOPSIS
    Initializes global variables based on the environment type and configuration settings.

.DESCRIPTION
    This function initializes global variables used in the script based on the configuration
    settings. It reads the configuration file (variables.yaml) and sets up the environment-specific variables
    required for the script execution.

.NOTES
    Requires the script "scripts\yaml_to_json.py" or executable "yaml_to_json.exe" to be available.

.EXAMPLE
    Initialize-Variables
    # Initializes the global variables based on the configuration file.
#>
function Initialize-Variables {
    $global:configParser = if (Test-Path -Path "scripts\yaml_to_json.py") { "python scripts\yaml_to_json.py" } else { "& .\yaml_to_json.exe" }
    $global:configFile = "config\variables.yaml"
    $global:VARIABLES = Invoke-Expression ($configParser + " " + $configFile) | ConvertFrom-Json

    if ($global:VARIABLES."ENVIRONMENT TYPE" -eq "prod") {
        $global:ROBOT_COMMAND = @("&", ".\run_tests.exe")
        Add-PathVariable "wc3270"
        Add-PathVariable "wkhtmltopdf"
        Add-PathVariable "fzf"
    }
    else {
        $global:ROBOT_COMMAND = @("python", ".\scripts\run_tests.py")
    }

    # Set fzf default options
    $env:FZF_DEFAULT_OPTS = "--height 85% --border sharp --layout reverse"
}

<#
.SYNOPSIS
    Initializes global variables for the specified version.

.DESCRIPTION
    This function sets up global variables related to the specified version. It configures variables
    such as the robot command, robot path, and others based on the provided version and environment type.

.PARAMETER version
    The version to initialize (e.g., "v1", "v2", "v1v2").

.PARAMETER testPath
    The path to the test directory. Defaults to "src\tests".

.EXAMPLE
    Initialize-Version "v1"
    # Initializes global variables for the "v1" version.
#>
function Initialize-Version {
    param (
        [string]$version,
        [string]$testPath = "src\tests"
    )

    $global:CARDLINK_VERSION = $version.ToUpper()

    if ($global:CARDLINK_VERSION -ne "V1V2") {
        $global:CARDS_KEY = $CARDLINK_VERSION.Replace("_", " ").ToUpper() + " CARDS"
        $global:MERCHANTS_KEY = $CARDLINK_VERSION.Replace("_", " ").ToUpper() + " MERCHANTS"
        $global:ROBOT_PATH = Join-Path $testPath $CARDLINK_VERSION.ToLower()
    
        if ($global:VARIABLES."ENVIRONMENT TYPE" -eq "prod") {
            $global:ROBOT_PATH += ".bin"
        }
        else {
            $global:ROBOT_PATH += ".robot"
        }
    }
    else {
        $global:V1_ROBOT_COMMAND = @()
        $global:V2_ROBOT_COMMAND = @()
        $global:CARDS_KEY = "V1V2 CARDS"
        $global:MERCHANTS_KEY = "V1V2 MERCHANTS"
        $global:V1_ROBOT_PATH = Join-Path $testPath "v1"
        $global:V2_ROBOT_PATH = Join-Path $testPath "v2"
    
        if ($global:VARIABLES."ENVIRONMENT TYPE" -eq "prod") {
            $global:V1_ROBOT_PATH += ".bin"
            $global:V2_ROBOT_PATH += ".bin"
        }
        else {
            $global:V1_ROBOT_PATH += ".robot"
            $global:V2_ROBOT_PATH += ".robot"
        }
    }
}

<#
.SYNOPSIS
    Retrieves the list of V1V2 test cases.

.DESCRIPTION
    This function retrieves the list of V1V2 test cases from the configuration file (v1v2_mapping.yaml) 
    and outputs their names. The V1V2 test cases are used in combined test runs to execute specific sets
    of tests for version 1 (V1) and version 2 (V2) separately.

.NOTES
    The function reads the V1V2 configuration file to obtain the test case information. The configuration
    file should be in YAML format.

.EXAMPLE
    Get-V1V2TestCases
    # Retrieves the list of V1V2 test case names and outputs them.
#>
function Get-V1V2TestCases {  
    $global:V1V2 = Invoke-Expression ($configParser + " config\v1v2_mapping.yaml") | ConvertFrom-Json

    foreach ($testCase in $V1V2."Test cases") {
        $table = @{}
        $testCase.psobject.properties | ForEach-Object { $table[$_.Name] = $_.Value }
        Write-Output $table.Keys[0]
    }
}

<#
.SYNOPSIS
    Adds test cases to the global robot command for execution.

.DESCRIPTION
    This function adds the specified test cases to the global robot command to be executed later. The function
    handles both single-version (v1 only or v2 only) and v1v2 combined test runs, and appends the test cases to 
    the appropriate robot command.

.PARAMETER testCases
    An array of test case names to be added to the robot command.
    
.NOTES
    If v1v2 combined tests are active (determined by $VARIABLES.V1V2.ACTIVE), the function adds the
    test cases to the respective v1 and v2 robot commands. Otherwise, the test cases are added directly to
    the global robot command.

.EXAMPLE
    Add-TestCases @("AUAI Onus", "AUAI Onus With AUQM Reversal")
    # Adds "AUAI Onus" and "AUAI Onus With AUQM Reversal" to the global robot command for execution.
#>
function Add-TestCases {
    param ([object]$testCases)

    if (-not $VARIABLES.V1V2.ACTIVE) {
        foreach ($testCase in $testCases) {
            $global:ROBOT_COMMAND += '--test "' + $testCase + '"'
        }
    }
    else {
        $testCase = $testCases[0]

        if ($global:V1V2."Test cases".$testCase.V1.Length -gt 0) {
            $global:V1_ROBOT_COMMAND += '--test "' + $global:V1V2."Test cases".$testCase.V1 + '"'
        }
        if ($global:V1V2."Test cases".$testCase.V2.Length -gt 0) {
            $global:V2_ROBOT_COMMAND += '--test "' + $global:V1V2."Test cases".$testCase.V2 + '"'
        }

        Add-TestVariable ([ref]$global:V1_ROBOT_COMMAND) "V1V2 TEST NAME" $testCase
        Add-TestVariable ([ref]$global:V2_ROBOT_COMMAND) "V1V2 TEST NAME" $testCase        
    }
}

<#
.SYNOPSIS
    Adds a test variable to the provided reference variable.

.DESCRIPTION
    This function constructs a test variable string in the format "--variable 'name:value'"
    and appends it to the reference variable.

.PARAMETER variableReference
    A reference to the variable to which the test variable string will be appended.

.PARAMETER variableName
    The name of the test variable.

.PARAMETER variableValue
    The value of the test variable.

.EXAMPLE
    $global:ROBOT_COMMAND = @()
    $variableRef = [ref]$global:ROBOT_COMMAND
    Add-TestVariable $variableRef "ONUS CARD" "0004447020050000018"
    # Appends `--variable "ONUS CARD:0004447020050000018"` to $global:ROBOT_COMMAND.
#>
function Add-TestVariable { 
    param (
        [ref]$variableReference,
        [string]$variableName,
        [string]$variableValue
    )

    $variableReference.value += '--variable "' + $variableName + ':' + $variableValue + '"'
}

<#
.SYNOPSIS
    Adds multiple test variables to the provided reference variable.

.DESCRIPTION
    This function constructs test variable strings in the format "--variable 'name:value'"
    and appends them to the reference variable.

.PARAMETER variableReference
    A reference to the variable to which the test variable strings will be appended.

.PARAMETER variableTable
    A hashtable containing the names and values of the test variables to be added.

.EXAMPLE
    $global:ROBOT_COMMAND = @()
    $variableRef = [ref]$global:ROBOT_COMMAND
    $variables = @{
        "OFFUS CARD" = "0004447020050000018"
        "OFFUS CARD EXPIRY" = "2806"
    }
    Add-TestVariables $variableRef $variables
    # Appends `--variable "ONUS CARD:0004447020050000018" --variable "OFFUS CARD EXPIRY:2806"` to $global:ROBOT_COMMAND.
#>
function Add-TestVariables {
    param (
        [ref]$variableReference,
        [hashtable]$variableTable
    )

    foreach ($key in $variableTable.Keys) {
        Add-TestVariable $variableReference -variableName $key -variableValue $variableTable.$key
    }
}

<#
.SYNOPSIS
    Select a card from a list of cards.

.DESCRIPTION
    This function is used to select a card in the given list of cards.
    The user will be prompted to select a card using the "fzf" utility.

.PARAMETER cards
    A list of cards to select from.

.PARAMETER comment
    The comment to be displayed in the "fzf" header.

.EXAMPLE
    Select-Card $cardsArray
    # Prompts the user to select a card using "fzf" and returns its index in the $cardsArray.
#>
function Select-Card {
    param (
        [object]$cards,
        [string]$comment = "Select Card Number:"
    )

    $cardList = Write-Output $cards `
    | ForEach-Object {
        $pan = $_.PAN
        $description = $_.DESCRIPTION

        $item = ""

        if ($pan.Length -gt 0) {
            $item += $pan
        }

        if ($description.Length -gt 0) {
            $item += " [" + $description + "]"
        }

        Write-Output $item
    }
    $card = Write-Output $cardList | fzf --header=$comment
    if (-not $card) {
        exit(0)
    }
    Write-Output ([array]::IndexOf($cardList, $card))
}

<#
.SYNOPSIS
    Adds test card variables to the global robot command.

.DESCRIPTION
    This function adds test card variables to the global robot command.
    The card variables are retrieved from the configuration file and
    appended to the robot command.

.PARAMETER testCases
    An array of test case names.

.EXAMPLE
    Add-TestCardVariables @("AUAI Onus", "AUAI Offus")
    # Adds onus & offus test card variables to the global robot command.
#>
function Add-TestCardVariables {
    param (
        [object]$testCases
    )

    $offUsTests = $false
    $onUsTests = $false
    $qrIssTests = $false
    $qrAcqTests = $false

    foreach ($testCase in $testCases) {
        if ($testCase.ToUpper() -like "*OFFUS*") {
            $offUsTests = $true
        }
        else {
            $onUsTests = $true
        }
        if ($testCase.ToUpper() -like "*QR ISS*") {
            $qrIssTests = $true
        }
        if ($testCase.ToUpper() -like "*QR ACQ*") {
            $qrAcqTests = $true
        }
    }        

    $offUsNetworks = $VARIABLES."OFF US CARDS" `
    | Get-Member -MemberType NoteProperty `
    | Select-Object -ExpandProperty Name

    $onUsNetworks = $VARIABLES.$CARDS_KEY `
    | Get-Member -MemberType NoteProperty `
    | Select-Object -ExpandProperty Name

    if ($offUsTests -and $onUsTests) {
        $networks = $onUsNetworks | Where-Object { $offUsNetworks -contains $_ }
    }
    elseif ($offUsTests) {
        $networks = $offUsNetworks
    }
    else {
        $networks = $onUsNetworks
    }

    $network = (Select-PaymentNetwork $networks).ToUpper()

    if (-not $VARIABLES.V1V2.ACTIVE) {
        $ref = [ref] $global:ROBOT_COMMAND

        if ($offUsTests) {
            $index = Select-Card $VARIABLES."OFF US CARDS".$network

            $testVariables = @{
                "OFFUS CARD"        = $VARIABLES."OFF US CARDS".$network[$index].PAN
                "OFFUS CARD EXPIRY" = $VARIABLES."OFF US CARDS".$network[$index].EXPIRY
                "OFFUS CARD CVV1"   = $VARIABLES."OFF US CARDS".$network[$index].CVV1
                "OFFUS CARD CVV2"   = $VARIABLES."OFF US CARDS".$network[$index].CVV2
            }

            Add-TestVariables $ref $testVariables
        }

        if ($onUsTests) {
            $index = Select-Card $VARIABLES.$CARDS_KEY.$network

            $testVariables = @{
                "ONUS CARD" = $VARIABLES.$CARDS_KEY.$network[$index].PAN
            }

            Add-TestVariables $ref $testVariables
        }
        
        if ($qrIssTests -or $qrAcqTests) {
            if ($qrIssTests) {
                $comment = "Select Merchant PAN:"
            }
            elseif ($qrAcqTests) {
                $comment = "Select Consumer PAN:"
            }
            $index = Select-Card -cards $VARIABLES."OFF US CARDS".$network -comment $comment

            $testVariables = @{
                "OFFUS CARD"        = $VARIABLES."OFF US CARDS".$network[$index].PAN
                "OFFUS CARD EXPIRY" = $VARIABLES."OFF US CARDS".$network[$index].EXPIRY
                "OFFUS CARD CVV1"   = $VARIABLES."OFF US CARDS".$network[$index].CVV1
                "OFFUS CARD CVV2"   = $VARIABLES."OFF US CARDS".$network[$index].CVV2
            }

            Add-TestVariables $ref $testVariables
        }
    }
    else {
        $v1Ref = [ref] $global:V1_ROBOT_COMMAND
        $v2Ref = [ref] $global:V2_ROBOT_COMMAND

        if ($offUsTests) {
            $index = Select-Card $VARIABLES."OFF US CARDS".$network

            $v2TestVariables = @{
                "OFFUS CARD"        = $VARIABLES."OFF US CARDS".$network[$index].PAN
                "OFFUS CARD EXPIRY" = $VARIABLES."OFF US CARDS".$network[$index].EXPIRY
                "OFFUS CARD CVV1"   = $VARIABLES."OFF US CARDS".$network[$index].CVV1
                "OFFUS CARD CVV2"   = $VARIABLES."OFF US CARDS".$network[$index].CVV2
            }

            Add-TestVariables $v2Ref $v2TestVariables
        }

        if ($onUsTests) {
            $index = Select-Card $VARIABLES.$CARDS_KEY.$network

            $v1TestVariables = @{
                "ONUS CARD" = $VARIABLES.$CARDS_KEY.$network[$index].PAN
            }

            Add-TestVariables $v1Ref $v1TestVariables

            if (($VARIABLES.$CARDS_KEY.$network[$index].EXPIRY -eq $null) -or
                ($VARIABLES.$CARDS_KEY.$network[$index].CVV1 -eq $null) -or
                ($VARIABLES.$CARDS_KEY.$network[$index].CVV2 -eq $null)) {
                Write-Host "Please set up expiry date, CVV1, and CVV2 for the selected card number in the configuration file (variables.yaml)."
                exit(0)
            }

            $v2TestVariables = @{
                "OFFUS CARD"        = $VARIABLES.$CARDS_KEY.$network[$index].PAN
                "OFFUS CARD EXPIRY" = $VARIABLES.$CARDS_KEY.$network[$index].EXPIRY
                "OFFUS CARD CVV1"   = $VARIABLES.$CARDS_KEY.$network[$index].CVV1
                "OFFUS CARD CVV2"   = $VARIABLES.$CARDS_KEY.$network[$index].CVV2
            }

            Add-TestVariables $v2Ref $v2TestVariables
        }
    }
}

<#
.SYNOPSIS
    Select a merchant from a list of merchants.

.DESCRIPTION
    This function is used to select a merchant in the given list of merchants.
    The user will be prompted to select a merchant using the "fzf" utility.

.PARAMETER merchants
    A list of merchants to select from.

.EXAMPLE
    Select-Merchant $merchantsArray
    # Prompts the user to select a merchant using "fzf" and returns its index in the $merchantsArray.
#>
function Select-Merchant {
    param (
        [object]$merchants
    )

    $merchantList = Write-Output $merchants `
    | ForEach-Object {
        $org = $_.ORG
        $id = $_.ID
        $currency = $_.CURRENCY
        $terminal = $_."EDC TERMINAL"
        $description = $_.DESCRIPTION

        $item = ""

        if ($org.Length -gt 0) {
            $item += $org + ','
        }

        $item += $id
        
        if ($currency.Length -gt 0) {
            $item += " (" + $currency + ")"
        }

        if ($terminal.Length -gt 0) {
            $item += " - Terminal: " + $terminal
        }

        if ($description.Length -gt 0) {
            $item += " [" + $description + "]"
        }

        Write-Output $item
    }
    $merchant = Write-Output $merchantList | fzf --header="Select Merchant:"
    if (-not $merchant) {
        exit(0)
    }
    Write-Output ([array]::IndexOf($merchantList, $merchant))
}

<#
.SYNOPSIS
    Adds test merchant variables to the global robot command.

.DESCRIPTION
    This function adds test merchant variables if acquiring test case(s) are performed.

.PARAMETER testCases
    An array of test case names.

.PARAMETER blacklistPatterns
    A list of blacklisted patterns. Test cases matching any of the patterns will be skipped.

.EXAMPLE
    Add-TestMerchantVariables @("AUAI Onus")
    # Selects a merchant variable and adds it to the global robot command

.EXAMPLE
    Add-TestMerchantVariables @("Incoming Transaction")
    # Skips merchant variable selection and addition
#>
function Add-TestMerchantVariables {
    param (
        [object]$testCases,
        [string[]]$blacklistPatterns = @("*INCOMING*", "*AIAI*", "*AIFA*", "*QR*")
    )

    $ref = [ref]$global:ROBOT_COMMAND 

    foreach ($testCase in $testCases) {
        $isBlacklisted = $false

        foreach ($pattern in $blacklistPatterns) {
            if ($testCase.ToUpper() -like $pattern) {
                $isBlacklisted = $true
                break
            }
        }

        if (!$isBlacklisted) {
            $index = Select-Merchant $VARIABLES.$MERCHANTS_KEY

            $testVariables = @{
                "MERCHANT ORG"      = $VARIABLES.$MERCHANTS_KEY[$index].ORG
                "MERCHANT NUMBER"   = $VARIABLES.$MERCHANTS_KEY[$index].ID
                "EDC TERMINAL"      = $VARIABLES.$MERCHANTS_KEY[$index]."EDC TERMINAL"
                "MERCHANT CURRENCY" = $VARIABLES.$MERCHANTS_KEY[$index].CURRENCY
            }

            Add-TestVariables $ref $testVariables
            break
        }
    }
}

<#
.SYNOPSIS
    Starts the robot test execution.

.PARAMETER resultsDir
    The path to the directory where the test results will be stored.

.DESCRIPTION
    This function starts the robot test execution based on the initialized robot command. The function
    handles the execution flow for both single-version (v1 only or v2 only) and v1v2 combined test runs.

.EXAMPLE
    Start-Robot
    # Starts the robot test execution based on the initialized robot command.
#>
function Start-Robot {
    param ([string]$resultsDir = "results\")
    
    if ($VARIABLES."ENVIRONMENT TYPE" -eq "prod") {
        $resultsDir = "..\" + $resultsDir
    }

    if (-not $VARIABLES.V1V2.ACTIVE) {
        $global:ROBOT_COMMAND += "--outputdir " + $resultsDir
        $global:ROBOT_COMMAND += '"' + $global:ROBOT_PATH + '"'
        Write-Host $global:ROBOT_COMMAND
        Invoke-Expression ($global:ROBOT_COMMAND -join " ")
        return
    }
 
    $scriptBlock = {
        param ($projectRoot, $command)
        Set-Location $projectRoot
        Write-Host $command
        Invoke-Expression $command
    }
    
    $v1Flag = $false
    $v2Flag = $false

    if ($global:V1_ROBOT_COMMAND -like "*--test*") {
        $global:V1_ROBOT_COMMAND += "--outputdir " + $resultsDir + "V1"
        $global:V1_ROBOT_COMMAND += '"' + $global:V1_ROBOT_PATH + '"'
        Add-TestVariable ([ref]$global:V2_ROBOT_COMMAND) "V1 OUTPUT FILE" ($resultsDir + "V1\output.xml")
        $v1Flag = $true
    }

    if ($global:V2_ROBOT_COMMAND -like "*--test*") {
        $global:V2_ROBOT_COMMAND += "--outputdir " + $resultsDir + "V2"
        $global:V2_ROBOT_COMMAND += '"' + $global:V2_ROBOT_PATH + '"'
        Add-TestVariable ([ref]$global:V1_ROBOT_COMMAND) "V2 OUTPUT FILE" ($resultsDir + "V2\output.xml")
        $v2Flag = $true
    }
    
    $commands = @()

    if ($v1Flag) { $commands += (($global:ROBOT_COMMAND + $global:V1_ROBOT_COMMAND) -join " ") }
    if ($v2Flag) { $commands += (($global:ROBOT_COMMAND + $global:V2_ROBOT_COMMAND) -join " ") }

    if ($commands.Length -gt 1) {
        for (
            $i = 0
            $i -lt $commands.Length
            $i++
        ) {
            Start-Job -ScriptBlock $scriptBlock -ArgumentList (Get-Location).Path, $commands[$i]
        }
        
        Get-Job | Wait-Job | Receive-Job
    }
    else {
        & $scriptBlock (Get-Location).Path $commands[0]
    }
}

<#
.SYNOPSIS
    Selects the Cardlink version interactively using fzf.
.DESCRIPTION
    This function gets all the Robot and binary files in the specified testPath folder and
    presents them to the user for selection using fzf (a command-line fuzzy finder). The
    selected version is returned.
#>
function Select-CardlinkVersion {
    $version = Get-ChildItem $testPath\*.robot, $testPath\*.bin `
    | Select-Object -ExpandProperty Name `
    | Foreach-Object { Write-Output ($_.ToString().Split('.')[0]) } `
    | fzf --header="Select Environment:"

    if (-not $version) {
        exit(0)
    }

    Write-Output $version
}

<#
.SYNOPSIS
    Selects the Robot test cases interactively using fzf.
.DESCRIPTION
    This function presents a list of available Robot test cases to the user for selection
    using fzf (a command-line fuzzy finder). If V1V2.ACTIVE is true, it uses the Get-V1V2TestCases
    function to get test cases; otherwise, it calls external executables to obtain the list.
    The selected test cases are returned.
#>
function Select-TestCases {
    $testCases = @()

    if (-not $VARIABLES.V1V2.ACTIVE) {
        if ($VARIABLES."ENVIRONMENT TYPE" -eq "prod") {
            $testCases = & .\list_tests.exe $ROBOT_PATH `
            | fzf --header="Select Test Case(s):" --multi
        }
        else {
            $testCases = python scripts\list_tests.py $ROBOT_PATH `
            | fzf --header="Select Test Case(s):" --multi
        }
    }
    else {
        $testCases = @(
            (Get-V1V2TestCases | fzf --header="Select Test Case:")
        )
    }

    if (-not $testCases) {
        exit(0)
    }

    Write-Output -NoEnumerate $testCases
}

<#
.SYNOPSIS
    Selects the payment network interactively using fzf.
.PARAMETER networks
    A list of payment networks to select from.
.DESCRIPTION
    This function retrieves the available payment network options from the $VARIABLES.$CARDS_KEY
    object and presents them to the user for selection using fzf (a command-line fuzzy finder).
    The selected payment network is returned.
#>
function Select-PaymentNetwork {
    param ([object] $networks)

    $network = Write-Output $networks `
    | fzf --header="Select Payment Network:"

    if (-not $network) {
        exit(0)
    }

    Write-Output $network
}

<#
.SYNOPSIS
    Initializes the script and calls other functions to perform the main operations.
.DESCRIPTION
    This function sets the script location and initializes the script variables. 
    It then calls other functions to select the Cardlink version, test
    cases, payment network, card, and merchant before starting the Robot test execution.
#>
function Invoke-Main {
    Set-Location $PSScriptRoot\..

    Initialize-Variables

    if (-not $VARIABLES.V1V2.ACTIVE) {
        $version = Select-CardlinkVersion
        Initialize-Version $version $testPath
    }
    else {
        Initialize-Version "v1v2" $testPath
    }

    $testCases = Select-TestCases
    Add-TestCases $testCases

    if ($testPath -ne "tests") {
        Add-TestCardVariables $testCases
        Add-TestMerchantVariables $testCases
    }

    Start-Robot
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-Main
}
