[CmdletBinding()]
param(
    [string]$ProjectRoot = "D:\OneDrive\Desktop\ARABIA STRIKE WORLD WAR\arabiastrike.worldwar",
    [string]$UERoot = "D:\UE_5.8",
    [string]$EvidenceRoot = "D:\ASWW_RUNTIME_EVIDENCE\ControlRigACLVerify"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Stop-Gate([string]$Reason, [int]$Code = 1) {
    Write-Host ""
    Write-Host "CONTROLRIG_ACL_RUNTIME_VERIFY=STOPPED" -ForegroundColor Red
    Write-Host "BLOCKER=$Reason" -ForegroundColor Red
    Write-Host "NO_PROJECT_FILES_WERE_MODIFIED" -ForegroundColor Green
    Write-Host "DO_NOT_COMMIT_DO_NOT_PULL_DO_NOT_RESET_DO_NOT_RESTORE" -ForegroundColor Yellow
    Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
    exit $Code
}

Set-Location $ProjectRoot
$env:GIT_PAGER = "cat"

$Branch = (& git branch --show-current).Trim()
Write-Host "BRANCH=$Branch" -ForegroundColor Cyan
if ($Branch -ne "codex/asww-development") {
    Stop-Gate "WRONG_BRANCH_$Branch" 10
}

$ProjectFile = Join-Path $ProjectRoot "ArabiaStrikeWorldWar.uproject"
$EditorCmd = Join-Path $UERoot "Engine\Binaries\Win64\UnrealEditor-Cmd.exe"

if (-not (Test-Path -LiteralPath $ProjectFile -PathType Leaf)) {
    Stop-Gate "UPROJECT_NOT_FOUND" 11
}
if (-not (Test-Path -LiteralPath $EditorCmd -PathType Leaf)) {
    Stop-Gate "UNREALEDITOR_CMD_NOT_FOUND" 12
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " LOCATE REQUIRED ENGINE PLUGINS" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$PluginRoots = @(
    (Join-Path $UERoot "Engine\Plugins")
)

$ControlRigDescriptor = Get-ChildItem -LiteralPath $PluginRoots[0] -File -Recurse -Filter "ControlRig.uplugin" -ErrorAction SilentlyContinue |
    Select-Object -First 1

$ACLDescriptor = Get-ChildItem -LiteralPath $PluginRoots[0] -File -Recurse -Filter "ACLPlugin.uplugin" -ErrorAction SilentlyContinue |
    Select-Object -First 1

Write-Host "CONTROLRIG_DESCRIPTOR=$($ControlRigDescriptor.FullName)"
Write-Host "ACLPLUGIN_DESCRIPTOR=$($ACLDescriptor.FullName)"

if (-not $ControlRigDescriptor) {
    Stop-Gate "CONTROLRIG_PLUGIN_DESCRIPTOR_NOT_FOUND" 13
}
if (-not $ACLDescriptor) {
    Stop-Gate "ACLPLUGIN_DESCRIPTOR_NOT_FOUND" 14
}

function Inspect-PluginDescriptor {
    param(
        [string]$Label,
        [System.IO.FileInfo]$Descriptor
    )

    $Json = Get-Content -Raw -LiteralPath $Descriptor.FullName | ConvertFrom-Json

    $EnabledByDefault = $false
    if ($Json.PSObject.Properties.Name -contains "EnabledByDefault") {
        $EnabledByDefault = [bool]$Json.EnabledByDefault
    }

    $CanContainContent = $false
    if ($Json.PSObject.Properties.Name -contains "CanContainContent") {
        $CanContainContent = [bool]$Json.CanContainContent
    }

    Write-Host "${Label}_ENABLED_BY_DEFAULT=$EnabledByDefault"
    Write-Host "${Label}_CAN_CONTAIN_CONTENT=$CanContainContent"

    $RuntimeModuleCount = 0
    $EditorModuleCount = 0
    $OtherModuleCount = 0

    if ($Json.PSObject.Properties.Name -contains "Modules") {
        foreach ($M in $Json.Modules) {
            $Name = [string]$M.Name
            $Type = [string]$M.Type
            $Phase = ""
            if ($M.PSObject.Properties.Name -contains "LoadingPhase") {
                $Phase = [string]$M.LoadingPhase
            }

            Write-Host "${Label}_MODULE=$Name TYPE=$Type LOADING_PHASE=$Phase"

            if ($Type -match '^(Runtime|RuntimeNoCommandlet|RuntimeAndProgram|ClientOnly|ServerOnly|CookedOnly)$') {
                $RuntimeModuleCount++
            }
            elseif ($Type -match 'Editor') {
                $EditorModuleCount++
            }
            else {
                $OtherModuleCount++
            }
        }
    }

    Write-Host "${Label}_RUNTIME_MODULE_COUNT=$RuntimeModuleCount"
    Write-Host "${Label}_EDITOR_MODULE_COUNT=$EditorModuleCount"
    Write-Host "${Label}_OTHER_MODULE_COUNT=$OtherModuleCount"

    return [PSCustomObject]@{
        EnabledByDefault = $EnabledByDefault
        CanContainContent = $CanContainContent
        RuntimeModuleCount = $RuntimeModuleCount
        EditorModuleCount = $EditorModuleCount
        OtherModuleCount = $OtherModuleCount
    }
}

$ControlRigInfo = Inspect-PluginDescriptor "CONTROLRIG" $ControlRigDescriptor
$ACLInfo = Inspect-PluginDescriptor "ACLPLUGIN" $ACLDescriptor

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PROJECT EXPLICIT PLUGIN REFERENCES" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$ProjectJson = Get-Content -Raw -LiteralPath $ProjectFile | ConvertFrom-Json
$ExplicitControlRig = $false
$ExplicitACL = $false

if ($ProjectJson.PSObject.Properties.Name -contains "Plugins") {
    foreach ($P in $ProjectJson.Plugins) {
        if ($P.Name -eq "ControlRig") {
            $ExplicitControlRig = [bool]$P.Enabled
        }
        if ($P.Name -eq "ACLPlugin") {
            $ExplicitACL = [bool]$P.Enabled
        }
    }
}

Write-Host "PROJECT_EXPLICIT_CONTROLRIG_ENABLED=$ExplicitControlRig"
Write-Host "PROJECT_EXPLICIT_ACLPLUGIN_ENABLED=$ExplicitACL"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " ASWW REAL UNREAL MOUNT + LOAD CHECK" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$PyFile = Join-Path $EvidenceRoot "verify_controllrig_acl_$Stamp.py"
$StdOut = Join-Path $EvidenceRoot "verify_controllrig_acl_$Stamp.stdout.log"
$StdErr = Join-Path $EvidenceRoot "verify_controllrig_acl_$Stamp.stderr.log"

$Python = @'
import unreal

registry = unreal.AssetRegistryHelpers.get_asset_registry()
try:
    registry.search_all_assets(True)
except Exception:
    pass

def count_mount(path):
    try:
        return len(registry.get_assets_by_path(path, recursive=True))
    except Exception:
        return -1

print(f"ASWW_PLUGIN_MOUNT_COUNT|/ControlRig|{count_mount('/ControlRig')}")
print(f"ASWW_PLUGIN_MOUNT_COUNT|/ACLPlugin|{count_mount('/ACLPlugin')}")

checks = [
    "/ACLPlugin/ACLAnimCurveCompressionSettings",
    "/ControlRig/Controls/ControlRigGizmoMaterial",
    "/ControlRig/Controls/DefaultGizmoLibraryNormalized",
]

for path in checks:
    exists = unreal.EditorAssetLibrary.does_asset_exist(path)
    obj = unreal.EditorAssetLibrary.load_asset(path) if exists else None
    cls = obj.get_class().get_name() if obj else "NONE"
    print(f"ASWW_PLUGIN_ASSET|{path}|EXISTS={exists}|LOAD={obj is not None}|CLASS={cls}")

print("ASWW_PLUGIN_VERIFY_DONE=TRUE")
'@

[IO.File]::WriteAllText($PyFile, $Python, [Text.UTF8Encoding]::new($false))
$PyForward = $PyFile.Replace('\','/')

$Args = @(
    $ProjectFile,
    "-unattended",
    "-nop4",
    "-nosplash",
    "-NullRHI",
    "-stdout",
    "-FullStdOutLogOutput",
    "-ExecutePythonScript=$PyForward"
)

$Proc = Start-Process `
    -FilePath $EditorCmd `
    -ArgumentList $Args `
    -WorkingDirectory $ProjectRoot `
    -PassThru `
    -Wait `
    -RedirectStandardOutput $StdOut `
    -RedirectStandardError $StdErr

$Exit = $Proc.ExitCode
Write-Host "UNREAL_EDITOR_CMD_EXIT=$Exit"

$Text = ""
if (Test-Path -LiteralPath $StdOut) {
    $Text += Get-Content -Raw -LiteralPath $StdOut
    Select-String -LiteralPath $StdOut -Pattern "ASWW_PLUGIN_" |
        ForEach-Object { Write-Host $_.Line }
}
if (Test-Path -LiteralPath $StdErr) {
    $Text += "`n" + (Get-Content -Raw -LiteralPath $StdErr)
}

$PythonError = $Text -match "(?i)LogPython:\s*Error|Traceback \(most recent call last\)"
$Fatal = $Text -match "(?im)^\s*Fatal error:|LowLevelFatalError|Unhandled Exception|Assertion failed:"

function Read-MountCount([string]$Mount) {
    $Esc = [regex]::Escape($Mount)
    $M = [regex]::Match($Text, "ASWW_PLUGIN_MOUNT_COUNT\|$Esc\|(-?\d+)")
    if ($M.Success) { return [int]$M.Groups[1].Value }
    return -1
}

$ControlRigMountCount = Read-MountCount "/ControlRig"
$ACLMountCount = Read-MountCount "/ACLPlugin"

$ACLAssetLoads = $Text -match 'ASWW_PLUGIN_ASSET\|/ACLPlugin/ACLAnimCurveCompressionSettings\|EXISTS=True\|LOAD=True'
$ControlRigGizmoLoads = $Text -match 'ASWW_PLUGIN_ASSET\|/ControlRig/Controls/ControlRigGizmoMaterial\|EXISTS=True\|LOAD=True'
$ControlRigLibraryLoads = $Text -match 'ASWW_PLUGIN_ASSET\|/ControlRig/Controls/DefaultGizmoLibraryNormalized\|EXISTS=True\|LOAD=True'

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " RUNTIME PLUGIN CLASSIFICATION" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

Write-Host "CONTROLRIG_MOUNT_ASSET_COUNT=$ControlRigMountCount"
Write-Host "ACLPLUGIN_MOUNT_ASSET_COUNT=$ACLMountCount"
Write-Host "ACL_COMPRESSION_ASSET_LOAD=$ACLAssetLoads"
Write-Host "CONTROLRIG_GIZMO_ASSET_LOAD=$ControlRigGizmoLoads"
Write-Host "CONTROLRIG_LIBRARY_ASSET_LOAD=$ControlRigLibraryLoads"
Write-Host "PYTHON_ERROR_SEEN=$PythonError"
Write-Host "FATAL_ERROR_SEEN=$Fatal"

if ($Exit -ne 0 -or $PythonError -or $Fatal) {
    Stop-Gate "UNREAL_PLUGIN_MOUNT_CHECK_FAILED" $(if ($Exit -gt 0) { $Exit } else { 20 })
}

$ControlRigRuntimeCapable = $ControlRigInfo.RuntimeModuleCount -gt 0
$ACLRuntimeCapable = $ACLInfo.RuntimeModuleCount -gt 0

Write-Host "CONTROLRIG_RUNTIME_CAPABLE=$ControlRigRuntimeCapable"
Write-Host "ACLPLUGIN_RUNTIME_CAPABLE=$ACLRuntimeCapable"

if ($ControlRigRuntimeCapable -and
    $ACLRuntimeCapable -and
    $ControlRigMountCount -gt 0 -and
    $ACLMountCount -gt 0 -and
    $ACLAssetLoads -and
    $ControlRigGizmoLoads) {

    Write-Host "REQUIRED_RUNTIME_PLUGIN_CLASSIFICATION=AVAILABLE_AND_MOUNTED_IN_ASWW" -ForegroundColor Green
    Write-Host "NEXT_GATE=COPY_VERIFIED_THIRDPERSON_GAME_DEPENDENCIES_AND_PACKAGE_WITH_EXISTING_ENGINE_PLUGINS" -ForegroundColor Green
}
elseif ($ControlRigRuntimeCapable -and
        $ACLRuntimeCapable -and
        ($ControlRigMountCount -eq 0 -or $ACLMountCount -eq 0)) {

    Write-Host "REQUIRED_RUNTIME_PLUGIN_CLASSIFICATION=RUNTIME_CAPABLE_BUT_NOT_MOUNTED_IN_ASWW" -ForegroundColor Yellow
    Write-Host "NEXT_GATE=ENABLE_ONLY_CONTROLRIG_AND_ACLPLUGIN_THEN_REVERIFY_BEFORE_COPY" -ForegroundColor Yellow
}
else {
    Write-Host "REQUIRED_RUNTIME_PLUGIN_CLASSIFICATION=NOT_CLEAN_FOR_DIRECT_TEMPLATE_ABP_REUSE" -ForegroundColor Yellow
    Write-Host "NEXT_GATE=IMPORT_MANNY_MESH_ONLY_AND_BUILD_MINIMAL_ASWW_ANIMATION_PATH" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "CONTROLRIG_ACL_RUNTIME_VERIFY=PASS" -ForegroundColor Green
Write-Host "NO_PROJECT_FILES_WERE_MODIFIED" -ForegroundColor Green
Write-Host "DO_NOT_COMMIT_YET" -ForegroundColor Yellow
Write-Host "DO_NOT_TOUCH_MAIN" -ForegroundColor Red
