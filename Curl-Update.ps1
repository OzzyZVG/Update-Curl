Set-ExecutionPolicy RemoteSigned
function Test-NetworkConnection {
    param (
        [string]$Computer
    )
    $isOnline = Test-Connection -ComputerName $Computer -Count 1 -Quiet
    if ($isOnline) {
        Write-Host ("Testing connection to " + $Computer + ": Online")
    } else {
        Write-Host ("Testing connection to " + $Computer + ": Offline")
    }
    return $isOnline
}
# Função para verificar e atualizar o Curl em uma máquina remota

function Update-Curl {
    # Remote session arguments
    $SessionArgs = @{
        ComputerName  = $Computer
        SessionOption = New-CimSessionOption -Protocol Dcom
    }
    
    param (
        [string]$Computer,
        [System.Management.Automation.PSCredential]$Credential,
        [string]$ComputerListFilePath,
        [ref]$FailedComputers
    )

    $currentUser = $env:USERNAME
    $tempPath = "C:\Temp\$currentUser"

    $curlZipPath = Join-Path $tempPath "curl.zip"
    $curlUrl = "https://curl.se/windows/dl-8.2.1_3/curl-8.2.1_3-win64-mingw.zip"

    $scriptBlock = {
        param (
            $tempPath,
            $curlZipPath,
            $curlUrl
        )

        # Create the temporary directory if it doesn't exist
        if (-not (Test-Path $tempPath)) {
            New-Item -Path $tempPath -ItemType Directory
        }

        $sourceCurlExe = Join-Path $tempPath "curl-8.2.1_3-win64-mingw\bin\curl.exe"

        Write-Output "Verifying current Curl version..."

        $versionInfo = (Get-Command $sourceCurlExe -ErrorAction SilentlyContinue).FileVersionInfo
        $currentVersion = $null
        if ($versionInfo -ne $null) {
            $currentVersion = $versionInfo.ProductVersion
        }

        Write-Output "Current Curl version: $currentVersion"

        if ($currentVersion -lt "8.2.1") {
            Write-Output "Downloading and extracting curl.zip..."
            Invoke-WebRequest -Uri $curlUrl -OutFile $curlZipPath
            Expand-Archive -Path $curlZipPath -DestinationPath $tempPath -Force

            Write-Output "Copying updated curl.exe to temp directory..."
            Copy-Item -Path $sourceCurlExe -Destination $tempPath -Force

            Remove-Item $curlZipPath -Force
        } else {
            Write-Output "Curl is up to date. No need to update."
        }
    }

    $moveScriptBlock = {
        param ($tempPath)
        
        $destinationCurlExe = "C:\Windows\System32\curl.exe"
        $destinationCurlExeSysWOW64 = "C:\Windows\SysWOW64\curl.exe"

        $sourceCurlExe = Join-Path $tempPath "curl.exe"

        # Create the destination directories if they don't exist
        if (-not (Test-Path $destinationCurlExe)) {
            New-Item -Path (Split-Path $destinationCurlExe) -ItemType Directory
        }
        if (-not (Test-Path $destinationCurlExeSysWOW64)) {
            New-Item -Path (Split-Path $destinationCurlExeSysWOW64) -ItemType Directory
        }

        # Verifica se o arquivo já existe em uma das pastas e move se necessário
        $curlExists = Test-Path $destinationCurlExe -PathType Leaf -ErrorAction SilentlyContinue
        $curlExistsSysWOW64 = Test-Path $destinationCurlExeSysWOW64 -PathType Leaf -ErrorAction SilentlyContinue

        if (-not $curlExists) {
            Write-Output "Moving updated curl.exe to C:\Windows\System32..."
            Move-Item -Path $sourceCurlExe -Destination $destinationCurlExe -Force
        }

        if (-not $curlExistsSysWOW64) {
            Write-Output "Moving updated curl.exe to C:\Windows\SysWOW64..."
            Move-Item -Path $sourceCurlExe -Destination $destinationCurlExeSysWOW64 -Force
        }
    }

    Write-Output "Accessing $Computer via PSRemoting..."
    try {
        $session = New-PSSession -ComputerName $Computer -Credential $Credential -ErrorAction Stop

        Write-Output "Executing on $Computer via PSRemoting..."
        Invoke-Command -Session $session -ScriptBlock $scriptBlock -ArgumentList $tempPath, $curlZipPath, $curlUrl
        Invoke-Command -Session $session -ScriptBlock $moveScriptBlock -ArgumentList $tempPath
        Remove-PSSession $session

        # Remove the hostname from the list of failed computers
        $FailedComputers.Value.Remove($Computer) | Out-Null

        # Remove the computer from the list of computers if it was successful
        if ($ComputerListFilePath -ne $null) {
            $newContent = Get-Content $ComputerListFilePath | Where-Object { $_ -ne $Computer }
            $newContent | Set-Content $ComputerListFilePath -Force
        }

        return
    } catch {
        Write-Output "Failed to access via hostname, trying by IP..."
    }

    $ipAddress = (Resolve-DnsName -Name $Computer).IPAddress
    if ($ipAddress -ne $null) {
        Write-Output "Accessing via IP - $ipAddress"
        try {
            Write-Output "Executing on $ipAddress by IP..."
            Invoke-Command -ComputerName $ipAddress -Credential $Credential -ScriptBlock $scriptBlock -ArgumentList $tempPath, $curlZipPath, $curlUrl -ErrorAction Stop
            Invoke-Command -ComputerName $ipAddress -Credential $Credential -ScriptBlock $moveScriptBlock -ArgumentList $tempPath

            # Remove the hostname from the list of failed computers
            $FailedComputers.Value.Remove($Computer) | Out-Null

            # Remove the computer from the list of computers if it was successful
            if ($ComputerListFilePath -ne $null) {
                $newContent = Get-Content $ComputerListFilePath | Where-Object { $_ -ne $Computer }
                $newContent | Set-Content $ComputerListFilePath -Force
            }

            return
        } catch {
            Write-Output "Failed to access via IP, trying via PSSession..."
        }
    } else {
        Write-Output "Unable to resolve IP for $Computer. Trying via PSSession..."
    }

    try {
        Write-Output "Executing on $Computer using PSsession..."
        Invoke-Command -ComputerName $Computer -Credential $Credential -ScriptBlock $scriptBlock -ArgumentList $tempPath, $curlZipPath, $curlUrl -ErrorAction Stop
        Invoke-Command -ComputerName $Computer -Credential $Credential -ScriptBlock $moveScriptBlock -ArgumentList $tempPath

        # Remove the hostname from the list of failed computers
        $FailedComputers.Value.Remove($Computer) | Out-Null

        # Remove the computer from the list of computers if it was successful
        if ($ComputerListFilePath -ne $null) {
            $newContent = Get-Content $ComputerListFilePath | Where-Object { $_ -ne $Computer }
            $newContent | Set-Content $ComputerListFilePath -Force
        }
    } catch {
        Write-Output "Failed to access $Computer via PSSession."
    }
}

# Define as credenciais
$Username = "a-borjano-1"
$Password = ConvertTo-SecureString "1@2l3l4a5N" -AsPlainText -Force
$Credential = New-Object System.Management.Automation.PSCredential($Username, $Password)

# Caminho para o arquivo de lista de computadores
$ComputerListFilePath = "C:\Temp\computer_list.txt"

# List of target computers (hostname or IP)
$Computers = Get-Content $ComputerListFilePath | Sort

# List to keep track of failed computers
$FailedComputers = [System.Collections.Generic.List[string]]::new()

# Loop através dos computadores
foreach ($Computer in $Computers) {
    Update-Curl -Computer $Computer -Credential $Credential -ComputerListFilePath $ComputerListFilePath -FailedComputers ([ref]$FailedComputers)
}

# Write the remaining failed computers back to the file
$FailedComputers | Set-Content $ComputerListFilePath -Force

# Function to test network connection
function Test-NetworkConnection {
    param (
        [string]$Computer
    )
    $isOnline = Test-Connection -ComputerName $Computer -Count 1 -Quiet
    $status = if ($isOnline) { "Online" } else { "Offline" }
    Write-Host ("Testing connection to " + $Computer + ": " + $status)
    return $isOnline
}

# Function to process computers in parallel
function Process-Computers {
    param (
        [string]$ComputerListFilePath,
        [System.Management.Automation.PSCredential]$Credential,
        [int]$ThrottleLimit = 10
    )
    
    # Log files
    $successLog = "C:\Temp\SuccessfulComputers.log"
    $failureLog = "C:\Temp\FailedComputers.log"

    # Clear previous logs
    if (Test-Path $successLog) { Remove-Item $successLog }
    if (Test-Path $failureLog) { Remove-Item $failureLog }

    # Read computer list from file
    $computers = Get-Content -Path $ComputerListFilePath

    # Parallel processing of computers with a throttle limit
    $computers | ForEach-Object -Parallel {
        $computer = $_
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

        # Check network connection
        if (Test-NetworkConnection -Computer $computer) {
            try {
                Update-Curl -Computer $computer -Credential $using:Credential
                Add-Content -Path $using:successLog -Value "$timestamp - $computer - Success"
            } catch {
                Add-Content -Path $using:failureLog -Value "$timestamp - $computer - Failed: $_"
            }
        } else {
            Add-Content -Path $using:failureLog -Value "$timestamp - $computer - Offline"
        }
    } -ThrottleLimit $ThrottleLimit

    # Generate final report
    Write-Host ("`nCompleted processing. Success log: " + $successLog)
    Write-Host ("Failure log: " + $failureLog)
}

# Main code execution
# Parameters can be adjusted as needed
$ComputerListFilePath = "C:\Temp\computer_list.txt"
$Credential = Get-Credential
$ThrottleLimit = 10

Process-Computers -ComputerListFilePath $ComputerListFilePath -Credential $Credential -ThrottleLimit $ThrottleLimit
