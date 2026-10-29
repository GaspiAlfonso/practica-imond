"""KPI Usuarios Activos: usuarios distintos con al menos una sesión web.

Usuario = el cliente si inició sesión; si es anónimo, cada sesión cuenta como un usuario
(ver supuestos en el README).

Los usuarios distintos NO se pueden sumar entre orígenes. Por eso cada archivo trae,
además de una fila por origen, una fila origen = 'Todos' con el total real del período.
En el dashboard usá esa fila para la tarjeta y la serie total.

Salidas: dw/kpi_usuarios_activos_diario.csv  y  dw/kpi_usuarios_activos_mensual.csv
"""
from _common import connect, save


def build_query(period_column: str) -> str:
    """period_column: columna de dim_date que define el período (full_date o year_month)."""
    return f"""
    SELECT d.{period_column} AS periodo,
           t.source_name AS origen,
           COUNT(DISTINCT w.active_user_key) AS usuarios_activos,
           COUNT(*) AS sesiones
    FROM fact_web_session AS w
    JOIN dim_date    AS d ON d.date_key    = w.date_key
    JOIN dim_traffic AS t ON t.traffic_key = w.traffic_key
    GROUP BY ALL
    UNION ALL
    SELECT d.{period_column}, 'Todos',
           COUNT(DISTINCT w.active_user_key), COUNT(*)
    FROM fact_web_session AS w
    JOIN dim_date AS d ON d.date_key = w.date_key
    GROUP BY ALL
    ORDER BY periodo, origen
    """


if __name__ == "__main__":
    con = connect()
    save(con, build_query("full_date"), "kpi_usuarios_activos_diario")
    save(con, build_query("year_month"), "kpi_usuarios_activos_mensual")
    mau = con.sql("""
        SELECT AVG(usuarios_activos) FROM read_csv('dw/kpi_usuarios_activos_mensual.csv')
        WHERE origen = 'Todos'
    """).fetchone()[0]
    print(f"Usuarios activos mensuales (promedio): {float(mau):,.0f}")