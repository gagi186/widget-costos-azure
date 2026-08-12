# Widget de costos Azure

Ventanita flotante para Windows que muestra el costo acumulado del mes de la suscripción de Azure: total, promedio diario, proyección a fin de mes, barras por día y desglose por servicio.

## Cómo funciona

- `CostosAzureWidget.ps1` — PowerShell 5.1 + WPF (guardado en UTF-8 **con BOM**; si se pierde el BOM, los acentos salen rotos). Usa la sesión activa de Azure CLI (`az login`) y consulta la API de Cost Management (con reintentos ante 429).
- `lanzar.vbs` — lo arranca sin ventana de consola (`wscript lanzar.vbs`).
- Se actualiza solo cada 4 horas; botón ⟳ para refrescar a mano.
- Se arrastra con el mouse y recuerda su posición en `cache.json` (ignorado en git, junto con `error.log`).

## Auto-arranque

Acceso directo "Costos Azure Widget" en la carpeta Inicio del usuario
(`shell:startup`), apuntando a `wscript.exe "…\lanzar.vbs"`.
