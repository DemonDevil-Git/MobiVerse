param([Parameter(Mandatory = $true)][string]$StatusPath)

$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="MobiVerse Setup" Width="520" Height="390" WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize" WindowStyle="None" AllowsTransparency="True" Background="Transparent" Topmost="True">
  <Border Background="#FFF9F1" BorderBrush="#1A142A33" BorderThickness="1" CornerRadius="22">
    <Border.Effect><DropShadowEffect BlurRadius="28" ShadowDepth="8" Opacity="0.22"/></Border.Effect>
    <Grid Margin="42,34,42,34">
      <Grid.RowDefinitions><RowDefinition Height="190"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
      <Canvas Width="190" Height="166" HorizontalAlignment="Center">
        <Ellipse Width="154" Height="154" Canvas.Left="18" Canvas.Top="4" Fill="#112E5973"/>
        <Path Fill="#F6F2E8" Stroke="#142A33" StrokeThickness="3" StrokeLineJoin="Round"
              Data="M34,42 C58,34 78,38 95,52 L95,137 C77,124 57,121 34,129 Z"/>
        <Path Fill="#FFFDF8" Stroke="#142A33" StrokeThickness="3" StrokeLineJoin="Round"
              Data="M156,42 C132,34 112,38 95,52 L95,137 C113,124 133,121 156,129 Z"/>
        <Path x:Name="PageOne" Fill="#FFFFFF" Stroke="#B84729" StrokeThickness="2.4" RenderTransformOrigin="0,0.5"
              Data="M95,52 C114,39 132,37 151,43 L151,119 C131,115 112,120 95,133 Z">
          <Path.RenderTransform><ScaleTransform ScaleX="1"/></Path.RenderTransform>
        </Path>
        <Path x:Name="PageTwo" Fill="#FFFFFF" Stroke="#2E5973" StrokeThickness="2.4" Opacity="0.9" RenderTransformOrigin="0,0.5"
              Data="M95,52 C112,42 128,40 145,45 L145,114 C127,112 111,118 95,130 Z">
          <Path.RenderTransform><ScaleTransform ScaleX="1"/></Path.RenderTransform>
        </Path>
        <Ellipse x:Name="Dot" Width="8" Height="8" Canvas.Left="91" Canvas.Top="151" Fill="#B84729"/>
      </Canvas>
      <TextBlock Grid.Row="1" Text="MobiVerse" FontFamily="Segoe UI Semibold" FontSize="25" Foreground="#142A33" HorizontalAlignment="Center"/>
      <TextBlock x:Name="Message" Grid.Row="2" Text="Preparing MobiVerse" Margin="0,9,0,0" FontFamily="Segoe UI" FontSize="14" Foreground="#6A7477" HorizontalAlignment="Center"/>
      <Grid Grid.Row="3" Margin="0,24,0,0" Height="6">
        <Border Background="#E4DED2" CornerRadius="3"/>
        <Border x:Name="ProgressBar" Background="#B84729" CornerRadius="3" HorizontalAlignment="Left" Width="20"/>
      </Grid>
      <TextBlock x:Name="Detail" Grid.Row="4" Margin="0,12,0,0" Text="This may take a few minutes" TextWrapping="Wrap" TextAlignment="Center" FontFamily="Segoe UI" FontSize="11" Foreground="#8A918F"/>
    </Grid>
  </Border>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)
$message = $window.FindName('Message')
$detail = $window.FindName('Detail')
$progressBar = $window.FindName('ProgressBar')
$pageOne = $window.FindName('PageOne')
$pageTwo = $window.FindName('PageTwo')
$dot = $window.FindName('Dot')

function Animate-Scale($element, [double]$delay) {
    $animation = New-Object Windows.Media.Animation.DoubleAnimation
    $animation.From = 1; $animation.To = 0.08
    $animation.Duration = [Windows.Duration]::new([TimeSpan]::FromMilliseconds(760))
    $animation.BeginTime = [TimeSpan]::FromMilliseconds($delay)
    $animation.AutoReverse = $true
    $animation.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
    $element.RenderTransform.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty, $animation)
}
Animate-Scale $pageOne 0
Animate-Scale $pageTwo 380
$pulse = New-Object Windows.Media.Animation.DoubleAnimation
$pulse.From = 0.25; $pulse.To = 1; $pulse.Duration = [Windows.Duration]::new([TimeSpan]::FromMilliseconds(700)); $pulse.AutoReverse = $true; $pulse.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
$dot.BeginAnimation([Windows.UIElement]::OpacityProperty, $pulse)

$script:completeAt = $null
$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(180)
$timer.Add_Tick({
    if (Test-Path -LiteralPath $StatusPath) {
        try {
            $status = Get-Content -LiteralPath $StatusPath -Raw | ConvertFrom-Json
            $message.Text = $status.message
            $detail.Text = if ($status.detail) { $status.detail } else { 'This may take a few minutes' }
            $progressBar.Width = [Math]::Max(12, [Math]::Min(436, 4.36 * [double]$status.progress))
            if ($status.stage -eq 'error') {
                $progressBar.Background = [Windows.Media.Brushes]::Firebrick
                $window.Topmost = $false
            }
            elseif ($status.stage -eq 'complete') {
                if ($null -eq $script:completeAt) { $script:completeAt = [DateTime]::Now }
                if (([DateTime]::Now - $script:completeAt).TotalMilliseconds -gt 1100) { $timer.Stop(); $window.Close() }
            }
        } catch { }
    }
})
$window.Add_Closed({ $timer.Stop() })
$timer.Start()
[void]$window.ShowDialog()
