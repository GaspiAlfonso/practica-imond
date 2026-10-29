"""KPI NPS: ((%promotores 9-10) - (%detractores 0-6)) * 100.

Salida: dw/kpi_nps_mensual.csv y dw/kpi_nps_diario.csv (período x canal, más canal 'Todos').
Trae los conteos para que el dashboard pueda recalcular el NPS de cualquier filtro:
    NPS = (SUM(promotores) - SUM(detractores)) / SUM(respuestas) * 100
"""
from _common import connect, save


def build_query(period_column: str) -> str:
    return f"""
    SELECT periodo, canal, respuestas, promotores, pasivos, detractores,
           (promotores - detractores) * 100.0 / respuestas AS nps
    FROM (
        SELECT d.{period_column} AS periodo, ch.name AS canal,
               COUNT(*) AS respuestas,
               COUNT(*) FILTER (WHERE n.nps_category = 'PROMOTER')  AS promotores,
               COUNT(*) FILTER (WHERE n.nps_category = 'PASSIVE')   AS pasivos,
               COUNT(*) FILTER (WHERE n.nps_category = 'DETRACTOR') AS detractores
        FROM fact_nps AS n
        JOIN dim_date    AS d  ON d.date_key     = n.date_key
        JOIN dim_channel AS ch ON ch.channel_key = n.channel_key
        GROUP BY ALL
        UNION ALL
        SELECT d.{period_column}, 'Todos',
               COUNT(*),
               COUNT(*) FILTER (WHERE n.nps_category = 'PROMOTER'),
               COUNT(*) FILTER (WHERE n.nps_category = 'PASSIVE'),
               COUNT(*) FILTER (WHERE n.nps_category = 'DETRACTOR')
        FROM fact_nps AS n
        JOIN dim_date AS d ON d.date_key = n.date_key
        GROUP BY ALL
    )
    ORDER BY periodo, canal
    """


if __name__ == "__main__":
    con = connect()
    save(con, build_query("year_month"), "kpi_nps_mensual")
    save(con, build_query("full_date"), "kpi_nps_diario")
    nps, n = con.sql("""
        SELECT (COUNT(*) FILTER (WHERE nps_category='PROMOTER') - COUNT(*) FILTER (WHERE nps_category='DETRACTOR'))
               * 100.0 / COUNT(*), COUNT(*) FROM fact_nps
    """).fetchone()
    print(f"NPS global: {nps:.1f}  ({n:,} respuestas)")