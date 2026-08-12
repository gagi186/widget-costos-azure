# Widget de costos Azure — ventana flotante con el acumulado del mes.
# Vistas: Mes (diario), 12 meses (mensual) y Todo (histórico).
# Requiere sesión activa de Azure CLI (az login). Se lanza oculto con lanzar.vbs.
# OJO: este archivo debe guardarse en UTF-8 CON BOM (PS 5.1 lee sin BOM como ANSI).

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
      <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
        <TextBlock x:Name="tabMes" Text="Mes" FontSize="11" Cursor="Hand" Margin="0,0,14,0"/>
        <TextBlock x:Name="tabMeses" Text="12 meses" FontSize="11" Cursor="Hand" Margin="0,0,14,0"/>
        <TextBlock x:Name="tabTodo" Text="Todo" FontSize="11" Cursor="Hand"/>
      </StackPanel>
      <TextBlock x:Name="txtEstado" Text="Cargando&#8230;" Foreground="#6E6E82" FontSize="10" Margin="0,8,0,0"/>
    </StackPanel>
  </Border>
</Window>
'@

$window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$ui = @{}
'txtTitulo','txtTotal','txtMoneda','txtSub','pnlBarras','pnlServicios','txtEstado',
'btnRefrescar','btnCerrar','tabMes','tabMeses','tabTodo' |
  ForEach-Object { $ui[$_] = $window.FindName($_) }

$sync = [hashtable]::Synchronized(@{ json = $null; fresh = $false; err = $null; busy = $false })
$script:lastData = $null
$script:jobs = @()
$script:nextFetch = Get-Date
$script:vista = 'mes'
$cult = [cultureinfo]::GetCultureInfo('es-MX')
$mesNombre = (Get-Date).ToString('MMMM', $cult)

$havePos = $false
if (Test-Path $cacheFile) {
  try {
    $c = Get-Content $cacheFile -Raw | ConvertFrom-Json
    if ($c.pos) { $window.Left = [double]$c.pos.x; $window.Top = [double]$c.pos.y; $havePos = $true }
    if ($c.vista -in @('mes','meses','todo')) { $script:vista = $c.vista }
    if ($c.json) {
      $tmp = $c.json | ConvertFrom-Json
      if ($tmp.mes -and $tmp.meses) { $sync.json = $c.json; $sync.fresh = $true }
    }
  } catch {}
}
if (-not $havePos) {
  $wa = [Windows.SystemParameters]::WorkArea
  $window.Left = $wa.Right - $window.Width - 16
  $window.Top = 16
}

function Save-State {
  try {
    @{ pos = @{ x = $window.Left; y = $window.Top }; vista = $script:vista; json = $sync.json } |
      ConvertTo-Json -Depth 10 | Set-Content -Path $cacheFile -Encoding UTF8
  } catch {}
}

function Nuevo-Brush([string]$hex) {
  New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($hex))
}

function Agrupa-Servicios($pares) {
  $h = @{}
  foreach ($p in $pares) {
    $k = [string]$p.n
    if (-not $h.ContainsKey($k)) { $h[$k] = 0.0 }
    $h[$k] += [double]$p.c
  }
  $lista = @()
  foreach ($k in $h.Keys) { $lista += [pscustomobject]@{ n = $k; c = $h[$k] } }
  @($lista | Sort-Object -Property c -Descending)
}

function Render-Barras($items) {
  $ui.pnlBarras.Children.Clear()
  $items = @($items)
  $max = 0.0
  foreach ($it in $items) { if ([double]$it.c -gt $max) { $max = [double]$it.c } }
  if ($max -le 0) { $max = 1 }
  $barW = [Math]::Max(4, [Math]::Min(18, [Math]::Floor(248 / [Math]::Max(1, $items.Count)) - 2))
  foreach ($it in $items) {
    $r = New-Object Windows.Shapes.Rectangle
    $r.Width = $barW
    $r.Height = [Math]::Max(3, [double]$it.c / $max * 44)
    $r.Fill = Nuevo-Brush '#3987E5'
    $r.RadiusX = 1.5; $r.RadiusY = 1.5
    $r.VerticalAlignment = 'Bottom'
    $r.Margin = New-Object Windows.Thickness(1, 0, 1, 0)
    $r.ToolTip = ('{0} · ${1}' -f $it.label, ([double]$it.c).ToString('N2', $cult))
    [void]$ui.pnlBarras.Children.Add($r)
  }
}

function Render-Servicios($svcs) {
  $ui.pnlServicios.Children.Clear()
  $svcs = @($svcs | Where-Object { [double]$_.c -ge 0.005 })
  $top = @($svcs | Select-Object -First 4)
  $resto = 0.0
  foreach ($s in @($svcs | Select-Object -Skip 4)) { $resto += [double]$s.c }
  $filas = @()
  foreach ($s in $top) { $filas += [pscustomobject]@{ n = [string]$s.n; c = [double]$s.c } }
  if ($resto -gt 0.005) { $filas += [pscustomobject]@{ n = 'Otros'; c = $resto } }
  $maxSvc = 0.0
  foreach ($s in $filas) { if ($s.c -gt $maxSvc) { $maxSvc = $s.c } }
  if ($maxSvc -le 0) { $maxSvc = 1 }
  foreach ($f in $filas) {
    $fila = New-Object Windows.Controls.DockPanel
    $tc = New-Object Windows.Controls.TextBlock
    $tc.Text = '$' + $f.c.ToString('N2', $cult)
    $tc.Foreground = Nuevo-Brush '#D8D8E4'
    $tc.FontSize = 12
    [Windows.Controls.DockPanel]::SetDock($tc, 'Right')
    $tn = New-Object Windows.Controls.TextBlock
    $tn.Text = $f.n
    $tn.Foreground = Nuevo-Brush '#9A9AB0'
    $tn.FontSize = 12
    $tn.TextTrimming = 'CharacterEllipsis'
    $tn.Margin = New-Object Windows.Thickness(0, 0, 8, 0)
    [void]$fila.Children.Add($tc)
    [void]$fila.Children.Add($tn)
    $barra = New-Object Windows.Controls.Border
    $barra.Height = 3
    $barra.CornerRadius = New-Object Windows.CornerRadius(1.5)
    $barra.Background = Nuevo-Brush '#3987E5'
    $barra.Width = [Math]::Max(6, $f.c / $maxSvc * 248)
    $barra.HorizontalAlignment = 'Left'
    $barra.Margin = New-Object Windows.Thickness(0, 3, 0, 7)
    [void]$ui.pnlServicios.Children.Add($fila)
    [void]$ui.pnlServicios.Children.Add($barra)
  }
}

function Render($d) {
  $totalTxt = { param($v) '$' + ([double]$v).ToString('N2', $cult) }
  $ui.txtMoneda.Text = $d.currency
  switch ($script:vista) {
    'meses' {
      $ult = @($d.meses | Select-Object -Last 12)
      $tot = 0.0; foreach ($m in $ult) { $tot += [double]$m.c }
      $ui.txtTitulo.Text = 'Costos Azure · por mes'
      $ui.txtTotal.Text = & $totalTxt $tot
      $prom = $tot / [Math]::Max(1, $ult.Count)
      $ui.txtSub.Text = ('últimos {0} meses · ~ ${1}/mes' -f $ult.Count, $prom.ToString('N2', $cult))
      Render-Barras $ult
      $yms = @{}; foreach ($m in $ult) { $yms[[string]$m.ym] = $true }
      Render-Servicios (Agrupa-Servicios @($d.mesSvc | Where-Object { $yms.ContainsKey([string]$_.ym) }))
    }
    'todo' {
      $tods = @($d.meses)
      $tot = 0.0; foreach ($m in $tods) { $tot += [double]$m.c }
      $ui.txtTitulo.Text = 'Costos Azure · histórico'
      $ui.txtTotal.Text = & $totalTxt $tot
      $prom = $tot / [Math]::Max(1, $tods.Count)
      $desde = if ($tods.Count -gt 0) { [string]$tods[0].label } else { '—' }
      $ui.txtSub.Text = ('desde {0} · ~ ${1}/mes' -f $desde, $prom.ToString('N2', $cult))
      Render-Barras @($tods | Select-Object -Last 40)
      Render-Servicios (Agrupa-Servicios @($d.mesSvc))
    }
    default {
      $ui.txtTitulo.Text = "Costos Azure · $mesNombre"
      $ui.txtTotal.Text = & $totalTxt $d.mes.total
      $dias = @($d.mes.daily).Count
      if ($dias -gt 0) {
        $prom = [double]$d.mes.total / $dias
        $enMes = [DateTime]::DaysInMonth((Get-Date).Year, (Get-Date).Month)
        $ui.txtSub.Text = ('~ ${0}/día · proyección ${1}' -f $prom.ToString('N2', $cult), ($prom * $enMes).ToString('N0', $cult))
      }
      Render-Barras @($d.mes.daily | ForEach-Object { [pscustomobject]@{ label = $_.d; c = $_.c } })
      Render-Servicios @($d.mes.services)
    }
  }
  foreach ($t in @(@($ui.tabMes, 'mes'), @($ui.tabMeses, 'meses'), @($ui.tabTodo, 'todo'))) {
    $t[0].Foreground = if ($script:vista -eq $t[1]) { Nuevo-Brush '#FFFFFF' } else { Nuevo-Brush '#6E6E82' }
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
    $url = "https://management.azure.com/subscriptions/$sub/providers/Microsoft.CostManagement/query?api-version=2023-03-01"
    function Invoke-CostApi([string]$body) {
      for ($i = 0; $i -lt 4; $i++) {
        try {
          return Invoke-RestMethod -Method Post -Uri $url -Headers @{ Authorization = "Bearer $token" } -ContentType 'application/json' -Body $body
        } catch {
          $code = 0; try { $code = [int]$_.Exception.Response.StatusCode } catch {}
          if ($code -eq 429 -and $i -lt 3) { Start-Sleep -Seconds (20 * ($i + 1)) } else { throw }
        }
      }
    }
    $cult = [cultureinfo]::GetCultureInfo('es-MX')
    $cur = 'USD'

    $bodyMes = @{
      type = 'ActualCost'; timeframe = 'MonthToDate'
      dataset = @{
        granularity = 'Daily'
        aggregation = @{ totalCost = @{ name = 'Cost'; function = 'Sum' } }
        grouping = @(@{ type = 'Dimension'; name = 'ServiceName' })
      }
    } | ConvertTo-Json -Depth 8
    $resp = Invoke-CostApi $bodyMes
    $porDia = @{}; $porSvc = @{}; $tot = 0.0
    foreach ($r in $resp.properties.rows) {
      $costo = [double]$r[0]; $fecha = [string][long]$r[1]; $svc = [string]$r[2]
      if ($r[3]) { $cur = [string]$r[3] }
      $tot += $costo
      if (-not $porDia.ContainsKey($fecha)) { $porDia[$fecha] = 0.0 }
      $porDia[$fecha] += $costo
      if (-not $porSvc.ContainsKey($svc)) { $porSvc[$svc] = 0.0 }
      $porSvc[$svc] += $costo
    }
    $daily = @($porDia.Keys | Sort-Object | ForEach-Object {
      @{ d = ([int]$_.Substring(6, 2)).ToString() + ' de ' + (Get-Date).ToString('MMM', $cult); c = [Math]::Round($porDia[$_], 4) }
    })
    $services = @($porSvc.GetEnumerator() | Sort-Object -Property Value -Descending | ForEach-Object {
      @{ n = $_.Key; c = [Math]::Round($_.Value, 4) }
    })

    $hoy = Get-Date
    $iniMesActual = Get-Date -Year $hoy.Year -Month $hoy.Month -Day 1 -Hour 0 -Minute 0 -Second 0
    $porMes = @{}; $porMesSvc = @{}
    for ($b = 0; $b -lt 10; $b++) {
      $fin = if ($b -eq 0) { $hoy } else { $iniMesActual.AddMonths(-12 * $b).AddDays(-1) }
      $ini = $iniMesActual.AddMonths(-11 - 12 * $b)
      $bodyHist = @{
        type = 'ActualCost'; timeframe = 'Custom'
        timePeriod = @{ from = $ini.ToString('yyyy-MM-ddT00:00:00Z'); to = $fin.ToString('yyyy-MM-ddT23:59:59Z') }
        dataset = @{
          granularity = 'Monthly'
          aggregation = @{ totalCost = @{ name = 'Cost'; function = 'Sum' } }
          grouping = @(@{ type = 'Dimension'; name = 'ServiceName' })
        }
      } | ConvertTo-Json -Depth 8
      $respH = $null
      try { $respH = Invoke-CostApi $bodyHist } catch { if ($b -eq 0) { throw } else { break } }
      $n = 0
      foreach ($r in $respH.properties.rows) {
        $costo = [double]$r[0]
        $dt = [datetime]::Parse([string]$r[1], [cultureinfo]::InvariantCulture)
        $svc = [string]$r[2]
        if ($r[3]) { $cur = [string]$r[3] }
        $ym = $dt.ToString('yyyy-MM')
        if (-not $porMes.ContainsKey($ym)) { $porMes[$ym] = 0.0 }
        $porMes[$ym] += $costo
        $k = $ym + '|' + $svc
        if (-not $porMesSvc.ContainsKey($k)) { $porMesSvc[$k] = 0.0 }
        $porMesSvc[$k] += $costo
        $n++
      }
      if ($n -eq 0) { break }
    }
    $meses = @($porMes.Keys | Sort-Object | ForEach-Object {
      $dt = [datetime]::ParseExact($_, 'yyyy-MM', [cultureinfo]::InvariantCulture)
      @{ ym = $_; label = $dt.ToString('MMM yy', $cult).Replace('.', ''); c = [Math]::Round($porMes[$_], 4) }
    })
    $mesSvc = @($porMesSvc.Keys | ForEach-Object {
      $partes = $_.Split('|', 2)
      @{ ym = $partes[0]; n = $partes[1]; c = [Math]::Round($porMesSvc[$_], 4) }
    })

    $sync.json = (@{
      currency = $cur; at = (Get-Date).ToString('HH:mm')
      mes = @{ total = [Math]::Round($tot, 4); daily = $daily; services = $services }
      meses = $meses; mesSvc = $mesSvc
    } | ConvertTo-Json -Depth 8)
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

function Set-Vista([string]$v) {
  $script:vista = $v
  if ($script:lastData) { Render $script:lastData }
  Save-State
}
$ui.tabMes.Add_MouseLeftButtonDown({ Set-Vista 'mes'; $_.Handled = $true })
$ui.tabMeses.Add_MouseLeftButtonDown({ Set-Vista 'meses'; $_.Handled = $true })
$ui.tabTodo.Add_MouseLeftButtonDown({ Set-Vista 'todo'; $_.Handled = $true })

$ui.btnRefrescar.Add_Click({ $script:nextFetch = Get-Date })
$ui.btnCerrar.Add_Click({ Save-State; $window.Close() })
$window.Add_MouseLeftButtonDown({ try { $window.DragMove(); Save-State } catch {} })
$window.Add_Closing({ Save-State })

[void]$window.ShowDialog()

} catch {
  $_ | Out-String | Set-Content -Path $logFile -Encoding UTF8
}
