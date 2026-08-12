# Widget de costos Azure — ventana flotante con el acumulado del mes.
# Requiere sesión activa de Azure CLI (az login). Se lanza oculto con lanzar.vbs.

$ErrorActionPreference = 'Stop'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$cacheFile = Join-Path $dir 'cache.json'
$logFile = Join-Path $dir 'error.log'

try {

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ShowInTaskbar="False" Topmost="False" SizeToContent="Height"
        Width="280" ResizeMode="NoResize" ShowActivated="False"
        WindowStartupLocation="Manual">
  <Border CornerRadius="14" Background="#F21E1E26" Padding="16,14,16,12">
    <StackPanel>
      <Grid Margin="0,0,0,6">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <TextBlock x:Name="txtTitulo" Text="Costos Azure" Foreground="#9A9AB0" FontSize="12" VerticalAlignment="Center"/>
        <Button x:Name="btnRefrescar" Grid.Column="1" Content="&#x27F3;" FontSize="14" Foreground="#9A9AB0" Background="Transparent" BorderThickness="0" Cursor="Hand" Padding="6,0" ToolTip="Actualizar ahora"/>
        <Button x:Name="btnCerrar" Grid.Column="2" Content="&#x2715;" FontSize="11" Foreground="#9A9AB0" Background="Transparent" BorderThickness="0" Cursor="Hand" Padding="6,0,0,0" ToolTip="Cerrar"/>
      </Grid>
      <StackPanel Orientation="Horizontal">
        <TextBlock x:Name="txtTotal" Text="&#8212;" Foreground="White" FontSize="30" FontWeight="SemiBold"/>
        <TextBlock x:Name="txtMoneda" Text="" Foreground="#9A9AB0" FontSize="13" VerticalAlignment="Bottom" Margin="6,0,0,6"/>
      </StackPanel>
      <TextBlock x:Name="txtSub" Text="" Foreground="#9A9AB0" FontSize="12" Margin="0,2,0,0"/>
      <StackPanel x:Name="pnlBarras" Orientation="Horizontal" Height="46" Margin="0,12,0,12"/>
      <StackPanel x:Name="pnlServicios"/>
      <TextBlock x:Name="txtEstado" Text="Cargando&#8230;" Foreground="#6E6E82" FontSize="10" Margin="0,8,0,0"/>
    </StackPanel>
  </Border>
</Window>
'@

$window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$ui = @{}
'txtTitulo','txtTotal','txtMoneda','txtSub','pnlBarras','pnlServicios','txtEstado','btnRefrescar','btnCerrar' |
  ForEach-Object { $ui[$_] = $window.FindName($_) }

$sync = [hashtable]::Synchronized(@{ json = $null; fresh = $false; err = $null; busy = $false })
$script:lastData = $null
$script:jobs = @()
$script:nextFetch = Get-Date

$mesNombre = (Get-Date).ToString('MMMM', [cultureinfo]::GetCultureInfo('es-MX'))
$ui.txtTitulo.Text = "Costos Azure · $mesNombre"

$havePos = $false
if (Test-Path $cacheFile) {
  try {
    $c = Get-Content $cacheFile -Raw | ConvertFrom-Json
    if ($c.pos) { $window.Left = [double]$c.pos.x; $window.Top = [double]$c.pos.y; $havePos = $true }
    if ($c.json) { $sync.json = $c.json; $sync.fresh = $true }
  } catch {}
}
if (-not $havePos) {
  $wa = [Windows.SystemParameters]::WorkArea
  $window.Left = $wa.Right - $window.Width - 16
  $window.Top = 16
}

function Save-State {
  try {
    @{ pos = @{ x = $window.Left; y = $window.Top }; json = $sync.json } |
      ConvertTo-Json -Depth 10 | Set-Content -Path $cacheFile -Encoding UTF8
  } catch {}
}

function Render($d) {
  $cult = [cultureinfo]::GetCultureInfo('es-MX')
  $ui.txtTotal.Text = '$' + ([double]$d.total).ToString('N2', $cult)
  $ui.txtMoneda.Text = $d.currency
  $dias = @($d.daily).Count
  if ($dias -gt 0) {
    $prom = [double]$d.total / $dias
    $enMes = [DateTime]::DaysInMonth((Get-Date).Year, (Get-Date).Month)
    $proy = $prom * $enMes
    $ui.txtSub.Text = ('~ ${0}/día · proyección ${1}' -f $prom.ToString('N2', $cult), $proy.ToString('N0', $cult))
  }

  $ui.pnlBarras.Children.Clear()
  $max = (@($d.daily) | Measure-Object -Property c -Maximum).Maximum
  if (-not $max -or $max -le 0) { $max = 1 }
  $barW = [Math]::Max(4, [Math]::Min(18, [Math]::Floor(248 / [Math]::Max(1, $dias)) - 2))
  foreach ($dia in $d.daily) {
    $r = New-Object Windows.Shapes.Rectangle
    $r.Width = $barW
    $r.Height = [Math]::Max(3, [double]$dia.c / $max * 44)
    $r.Fill = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString('#3987E5'))
    $r.RadiusX = 1.5; $r.RadiusY = 1.5
    $r.VerticalAlignment = 'Bottom'
    $r.Margin = New-Object Windows.Thickness(1, 0, 1, 0)
    $r.ToolTip = ('{0} · ${1}' -f $dia.d, ([double]$dia.c).ToString('N2', $cult))
    [void]$ui.pnlBarras.Children.Add($r)
  }

  $ui.pnlServicios.Children.Clear()
  $svcs = @($d.services | Where-Object { [double]$_.c -ge 0.005 })
  $top = @($svcs | Select-Object -First 4)
  $resto = ($svcs | Select-Object -Skip 4 | Measure-Object -Property c -Sum).Sum
  $filas = @()
  foreach ($s in $top) { $filas += [pscustomobject]@{ n = [string]$s.n; c = [double]$s.c } }
  if ($resto -gt 0.005) { $filas += [pscustomobject]@{ n = 'Otros'; c = [double]$resto } }
  $maxSvc = 0.0
  foreach ($s in $filas) { if ($s.c -gt $maxSvc) { $maxSvc = $s.c } }
  if ($maxSvc -le 0) { $maxSvc = 1 }
  foreach ($f in $filas) {
    $fila = New-Object Windows.Controls.DockPanel
    $tc = New-Object Windows.Controls.TextBlock
    $tc.Text = '$' + $f.c.ToString('N2', $cult)
    $tc.Foreground = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString('#D8D8E4'))
    $tc.FontSize = 12
    [Windows.Controls.DockPanel]::SetDock($tc, 'Right')
    $tn = New-Object Windows.Controls.TextBlock
    $tn.Text = $f.n
    $tn.Foreground = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString('#9A9AB0'))
    $tn.FontSize = 12
    $tn.TextTrimming = 'CharacterEllipsis'
    $tn.Margin = New-Object Windows.Thickness(0, 0, 8, 0)
    [void]$fila.Children.Add($tc)
    [void]$fila.Children.Add($tn)
    $barra = New-Object Windows.Controls.Border
    $barra.Height = 3
    $barra.CornerRadius = New-Object Windows.CornerRadius(1.5)
    $barra.Background = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString('#3987E5'))
    $barra.Width = [Math]::Max(6, $f.c / $maxSvc * 248)
    $barra.HorizontalAlignment = 'Left'
    $barra.Margin = New-Object Windows.Thickness(0, 3, 0, 7)
    [void]$ui.pnlServicios.Children.Add($fila)
    [void]$ui.pnlServicios.Children.Add($barra)
  }

  $ui.txtEstado.Text = "Actualizado $($d.at)"
}

$fetchScript = {
  param($sync)
  try {
    $sync.busy = $true
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    function Invoke-Az([string]$argLine) {
      $psi = New-Object System.Diagnostics.ProcessStartInfo
      $psi.FileName = 'cmd.exe'
      $psi.Arguments = '/c az ' + $argLine
      $psi.CreateNoWindow = $true
      $psi.UseShellExecute = $false
      $psi.RedirectStandardOutput = $true
      $psi.RedirectStandardError = $true
      $p = [System.Diagnostics.Process]::Start($psi)
      $out = $p.StandardOutput.ReadToEnd()
      $p.WaitForExit()
      $out.Trim()
    }
    $sub = Invoke-Az 'account show --query id -o tsv'
    if (-not $sub) { throw "Sin sesión de Azure: corre 'az login'" }
    $token = Invoke-Az 'account get-access-token --query accessToken -o tsv'
    if (-not $token) { throw 'No se pudo obtener token de Azure' }

    $body = @{
      type = 'ActualCost'; timeframe = 'MonthToDate'
      dataset = @{
        granularity = 'Daily'
        aggregation = @{ totalCost = @{ name = 'Cost'; function = 'Sum' } }
        grouping = @(@{ type = 'Dimension'; name = 'ServiceName' })
      }
    } | ConvertTo-Json -Depth 8
    $url = "https://management.azure.com/subscriptions/$sub/providers/Microsoft.CostManagement/query?api-version=2023-03-01"

    $resp = $null
    for ($i = 0; $i -lt 4; $i++) {
      try {
        $resp = Invoke-RestMethod -Method Post -Uri $url -Headers @{ Authorization = "Bearer $token" } -ContentType 'application/json' -Body $body
        break
      } catch {
        $code = 0; try { $code = [int]$_.Exception.Response.StatusCode } catch {}
        if ($code -eq 429 -and $i -lt 3) { Start-Sleep -Seconds (20 * ($i + 1)) } else { throw }
      }
    }

    $porDia = @{}; $porSvc = @{}; $cur = 'USD'; $tot = 0.0
    foreach ($r in $resp.properties.rows) {
      $costo = [double]$r[0]
      $fecha = [string][long]$r[1]
      $svc = [string]$r[2]
      if ($r[3]) { $cur = [string]$r[3] }
      $tot += $costo
      if (-not $porDia.ContainsKey($fecha)) { $porDia[$fecha] = 0.0 }
      $porDia[$fecha] += $costo
      if (-not $porSvc.ContainsKey($svc)) { $porSvc[$svc] = 0.0 }
      $porSvc[$svc] += $costo
    }
    $daily = @($porDia.Keys | Sort-Object | ForEach-Object {
      @{ d = ([int]$_.Substring(6, 2)).ToString() + ' de ' + (Get-Date).ToString('MMM', [cultureinfo]::GetCultureInfo('es-MX')); c = [Math]::Round($porDia[$_], 4) }
    })
    $services = @($porSvc.GetEnumerator() | Sort-Object -Property Value -Descending | ForEach-Object {
      @{ n = $_.Key; c = [Math]::Round($_.Value, 4) }
    })

    $sync.json = (@{
      total = [Math]::Round($tot, 4); currency = $cur
      at = (Get-Date).ToString('HH:mm'); daily = $daily; services = $services
    } | ConvertTo-Json -Depth 6)
    $sync.fresh = $true
  } catch {
    $sync.err = $_.Exception.Message
  } finally {
    $sync.busy = $false
  }
}

function Start-Fetch {
  if ($sync.busy) { return }
  $script:nextFetch = (Get-Date).AddHours(4)
  $ui.txtEstado.Text = 'Actualizando…'
  $rs = [runspacefactory]::CreateRunspace()
  $rs.Open()
  $ps = [powershell]::Create()
  $ps.Runspace = $rs
  [void]$ps.AddScript($fetchScript).AddArgument($sync)
  $script:jobs += @{ ps = $ps; rs = $rs; h = $ps.BeginInvoke() }
}

$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(1)
$timer.Add_Tick({
  if ($sync.fresh) {
    $sync.fresh = $false
    try {
      $d = $sync.json | ConvertFrom-Json
      $script:lastData = $d
      Render $d
      Save-State
    } catch { $ui.txtEstado.Text = 'Error al leer datos' }
  }
  if ($sync.err) {
    $ui.txtEstado.Text = $sync.err
    $sync.err = $null
    if (-not $script:lastData) { $script:nextFetch = (Get-Date).AddMinutes(2) }
  }
  if ((Get-Date) -ge $script:nextFetch) { Start-Fetch }
})
$timer.Start()

$ui.btnRefrescar.Add_Click({ $script:nextFetch = Get-Date })
$ui.btnCerrar.Add_Click({ Save-State; $window.Close() })
$window.Add_MouseLeftButtonDown({ try { $window.DragMove(); Save-State } catch {} })
$window.Add_Closing({ Save-State })

[void]$window.ShowDialog()

} catch {
  $_ | Out-String | Set-Content -Path $logFile -Encoding UTF8
}
