# Campamento 2026 · App offline

App web instalable (PWA) para consultar el programa, el rally, comunión.com, los deportes y los responsables del campamento *Tiempo de conquistar 2026*. Después de abrirla una vez, funciona sin internet.

- **Hoy**: qué está pasando ahora y qué sigue.
- **Programa**: miércoles a domingo, con responsables y notas.
- **Rally**: recorrido por equipo, tabla por ronda o por estación, y las plenarias del sábado.
- **Comunión.com** y **Deportes** (jueves, viernes, sábado).
- **Buscar** (lupa): escribe un nombre y ves todo lo que le toca a esa persona.

## Publicarla
Debe servirse por HTTPS (por ejemplo GitHub Pages) para poder instalarla. Abre el enlace en el celular y usa
"Agregar a pantalla de inicio" (iPhone: Compartir → Agregar a inicio; Android: menú → Instalar app).

## Corregir datos
Todos los datos están en `data.js`. Después de editarlo, cambia la versión de `CACHE` en `sw.js`
(por ejemplo `v2`) para que los teléfonos descarguen la nueva versión la próxima vez que tengan internet.
