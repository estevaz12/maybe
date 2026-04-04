---
name: presupuesto-mensual
description: >
  Automatiza el proceso mensual de presupuesto de Esteban: recolecta transacciones de 6 cuentas argentinas
  (Naranja X, Mercado Pago, Galicia, tarjetas de credito Galicia MC/Visa, NaranjaX MC), las normaliza a CSV,
  las carga en Maybe, actualiza el Excel de presupuesto con tipo de cambio blue y calcula cuanto USD enviar.
  Usa este skill cuando el usuario mencione presupuesto, budget, transacciones del mes, cargar transacciones,
  actualizar el Excel de presupuesto, calcular cuanto cambiar, dolar blue, o cualquier paso del proceso mensual
  de finanzas personales. Tambien cuando diga "es hora del presupuesto", "hagamos el presupuesto de [mes]",
  "ya tengo los CSVs", "necesito actualizar Maybe", o cualquier variacion. Incluso si solo menciona una cuenta
  especifica (Galicia, Mercado Pago, Naranja X) en contexto de transacciones o extractos, este skill aplica.
---

# Presupuesto Mensual - Guia de Automatizacion

Este skill guia el proceso completo de presupuesto mensual. El flujo tiene 6 fases que se ejecutan en orden.
Algunas fases son completamente automaticas, otras necesitan input del usuario. El skill esta disenado para
minimizar el tiempo y esfuerzo manual.

## Antes de empezar

Pregunta al usuario por que mes esta haciendo el presupuesto si no lo menciono. Normalmente es el mes anterior
al actual.

## Fase 1: Recolectar transacciones

El objetivo es obtener un CSV de cada cuenta. Hay 6 fuentes, cada una con su propio proceso.

### 1.1 Naranja X (cuenta debito)

**Requiere input manual** - Es una app de telefono, no se puede automatizar la extraccion.

Pedile al usuario que:

1. Abra la app de Naranja X en su telefono
2. Filtre por el mes correspondiente
3. Saque screenshots de TODAS las transacciones
4. Suba las screenshots aca

Una vez que tengas los screenshots, extrae las transacciones a CSV con este formato:

```
date,amount,name,currency
YYYY-MM-DD,-1234.56,Descripcion de la transaccion,ARS
```

- Fechas en formato YYYY-MM-DD
- Montos negativos para gastos, positivos para ingresos
- Moneda siempre ARS

Guarda como `naranjax_[YYYY-MM].csv` en el directorio de trabajo.

### 1.2 Mercado Pago

**Semi-automatico** - Navegar la web y descargar.

1. Navega a https://www.mercadopago.com.ar/balance/reports/account_status?cardPosition=0
2. Busca si ya hay un reporte generado para el mes correspondiente
3. Si no hay, genera uno nuevo para el periodo del mes
4. Descarga el CSV (pedir permiso al usuario antes de descargar)
5. El CSV de Mercado Pago suele venir con columnas como: DATE, DESCRIPTION, NET_CREDIT_AMOUNT, etc.

Normaliza al formato estandar y guarda como `mercadopago_[YYYY-MM].csv`.

**Nota:** El usuario necesita estar logueado. Si la pagina pide login, avisale para que lo haga manualmente.

### 1.3 Galicia (cuenta debito)

**Semi-automatico** - Navegar la web, descargar y limpiar.

1. Navega a https://cuentas.bancogalicia.com.ar/cuentas/mis-cuentas
2. Filtra por el mes correspondiente
3. Descarga el Excel de transacciones (pedir permiso antes)
4. Limpia el Excel: quita headers extra, filas vacias, formateo del banco
5. Convierte a CSV normalizado

Guarda como `galicia_[YYYY-MM].csv`.

**Nota:** El usuario necesita estar logueado. Si la pagina pide login, avisale.

### 1.4 Galicia MC (tarjeta de credito Mastercard)

**Semi-automatico** - Depende de si el PDF del resumen esta disponible.

Opciones:

- Si el usuario ya tiene el PDF: pedile que lo suba
- Si esta disponible en la web del banco: navega y descarga (con permiso)
- Si llego por email: pedile que lo suba

Una vez que tengas el PDF, usa el skill de PDF para extraer el texto, luego parsea las transacciones.
Los resumenes de Galicia MC tipicamente tienen este formato:

- Fecha, descripcion, monto, cuotas (si aplica)
- Montos en ARS

Extrae y normaliza a CSV. Guarda como `galicia_mc_[YYYY-MM].csv`.

### 1.5 Galicia Visa (tarjeta de credito Visa)

**Mismo proceso que Galicia MC.** Guarda como `galicia_visa_[YYYY-MM].csv`.

### 1.6 NaranjaX MC (tarjeta de credito Mastercard)

**Mismo proceso que las tarjetas de Galicia.** Guarda como `naranjax_mc_[YYYY-MM].csv`.

### Al terminar la Fase 1

Muestra un resumen de todos los CSVs generados con cantidad de transacciones y total por cuenta.
Pregunta si falta alguna cuenta o si hay que corregir algo antes de seguir.

## Fase 2: Cargar en Maybe

Maybe es una app de presupuesto open-source (Rails) que Esteban corre localmente en Docker via WSL.

### Formato CSV para Maybe

Maybe espera CSVs con estas columnas (el mapeo se hace en la UI):

```
date,amount,name,currency,category,tags,account,notes
```

Campos requeridos: date, amount. El resto es opcional pero util.

**Convencion de signos en Maybe:**

- Montos positivos = outflows (gastos)
- Montos negativos = inflows (ingresos)

### Proceso de carga

Para cada CSV normalizado:

1. Prepara el archivo en el formato que Maybe espera
2. Indica al usuario que suba el CSV a Maybe via la UI web (http://localhost:3000 o la URL que use)
3. El mapeo de columnas se hace en la UI de Maybe interactivamente
4. Las categories se asignan automaticamente via Rules que ya tiene configurados

Alternativamente, si la API esta habilitada, se puede usar:

```
POST /api/v1/transactions
Headers: X-Api-Key: [key]
Body: { "transaction": { "account_id": "...", "date": "...", "amount": ..., "name": "...", "nature": "expense" } }
```

Preguntale al usuario cual metodo prefiere. Si quiere usar la API, necesitaras el API key y los account IDs.

### Despues de cargar

Decile al usuario que revise las categorias en Maybe y confirme cuando este listo para continuar.

## Fase 3: Actualizar el Excel de presupuesto

El Excel esta en: La carpeta Personal montada del usuario (`Presupuesto.xlsx`).

Lee la referencia `references/excel-structure.md` para entender la estructura exacta del Excel.

### 3.1 Obtener el tipo de cambio

Necesitas dos valores de https://www.dolarito.ar/cotizacion/cripto-usdt-hoy:

- **Fiwind "Vende A:"** - Tipo de cambio para los primeros 1500 USD
- **Airtm "Vende A:"** - Tipo de cambio para el resto

Scrapeá la pagina para obtener estos valores. Luego calcula un tipo de cambio promedio ponderado:

```
tipo_cambio_promedio = (1500 * tasa_fiwind + resto_usd * tasa_airtm) / total_usd
```

O usa el valor de Airtm como el tipo de cambio principal para F2 si el usuario lo prefiere.

### 3.2 Obtener datos de inflacion

Busca el dato de inflacion del mes (IPC INDEC Argentina) para actualizar F3 si cambio.

### 3.3 Datos a ingresar en el Excel

En la hoja "mensual", para el mes correspondiente:

**Template area (filas 1-32):**

- F2: Actualizar tipo de cambio blue/cripto
- F3: Actualizar inflacion si cambio
- B27: Total a pagar de tarjetas de credito (suma de Galicia MC + Galicia Visa + NaranjaX MC)
- Actualizar valores de servicios si cambiaron (B9-B11, B14, B16, etc.)

**Area historica del mes (el bloque de ~12 filas del mes):**

- J3: Total gastado en efectivo (cash)
- J4: Total de salidas con tarjeta
- J5: Total de compras con tarjeta
- J8: Extras no presupuestados
- K3, K4, K5: Valores presupuestados (actualizar si cambiaron)

**Importante:** Usa el xlsx skill para leer y editar el archivo. Las formulas existentes se deben preservar intactas.
Solo modifica las celdas de datos (valores hardcoded), nunca las formulas.

### 3.4 Verificar calculos

Despues de actualizar, lee los valores calculados para verificar:

- B31/C31: Diferencia (lo que necesita cambiar)
- B32/C32: Monto a cambiar (redondeado)
- Que el balance cuadre

## Fase 4: Calcular USD a enviar

Con los datos del Excel actualizados:

1. Lee B31 o C31 (Diferencia) - es lo que falta cubrir
2. Calcula cuanto enviar:
   - Primeros 1500 USD via Fiwind (tasa Fiwind de dolarito.ar)
   - El resto via Airtm (tasa Airtm de dolarito.ar)
3. Presenta el resumen:

   ```
   Gastos totales: $X ARS
     Efectivo: $X ARS
     Tarjetas: $X ARS
   Dinero disponible: $X ARS
   Diferencia a cubrir: $X ARS ($Y USD)

   Enviar via Fiwind: 1,500 USD (= $X ARS a tasa $Z)
   Enviar via Airtm: $W USD (= $X ARS a tasa $Z)
   Total a enviar: $T USD
   ```

## Fase 5: Factura Monotributo (ARCA)

**Requiere input manual para login.**

1. Navega a https://auth.afip.gob.ar/contribuyente_/login.xhtml
2. Pedile al usuario que se loguee con su CUIT/CUIL y clave fiscal
3. Una vez logueado, navega a Comprobantes en Linea > Generar Comprobante
4. Guia al usuario en la generacion de la factura

**Nota:** Este paso es opcional y el usuario puede preferir hacerlo por su cuenta.

## Fase 6: Resumen final

Presenta un resumen completo del mes:

- Todas las transacciones cargadas (cantidad por cuenta)
- Presupuesto vs real por categoria
- Monto a cambiar y como distribuirlo (Fiwind/Airtm)
- Carryover al proximo mes
- Cualquier observacion (gastos inusuales, categorias que se pasaron, etc.)

## Notas generales

- Todo el proceso se puede hacer en partes. Si el usuario solo quiere hacer un paso, ayudalo con ese paso.
- Siempre confirma antes de modificar el Excel o descargar archivos.
- Los montos en Argentina usan formato con punto como separador de miles y coma para decimales (1.234,56),
  pero en los CSVs usa el formato internacional (1234.56) para compatibilidad.
- El skill de xlsx es necesario para editar el Excel. Leelo antes de tocar el archivo.
