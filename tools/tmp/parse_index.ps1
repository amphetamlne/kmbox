$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$json = Get-Content -Raw -Encoding UTF8 D:\Project\c++\kmbox\tools\tmp\pico_index.json | ConvertFrom-Json
Write-Output "顶层键: $($json.PSObject.Properties.Name -join ', ')"
# 遍历找出所有 windows 平台的工具条目
function Dump($node, $path) {
    if ($node -is [System.Collections.IEnumerable] -and $node -isnot [string]) {
        foreach ($item in $node) { Dump $item $path }
    } elseif ($node -is [PSCustomObject]) {
        $props = $node.PSObject.Properties.Name
        if ($props -contains 'name' -and $props -contains 'platforms') {
            foreach ($p in $node.platforms) {
                if ($p.os -eq 'windows' -or $p.platform -eq 'windows') {
                    Write-Output ("[{0}] v{1} -> {2}" -f $node.name, $node.version, $p.url)
                }
            }
        } else {
            foreach ($prop in $node.PSObject.Properties) { Dump $prop.Value "$path.$($prop.Name)" }
        }
    }
}
Dump $json ''
