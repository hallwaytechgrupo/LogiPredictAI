"""Pacote logipredict — pipeline de machine learning para previsão de atraso em entregas.

Submódulos:
    prepare: ETL dos dados brutos da Olist.
    prepare_olist_csv: Conversão simplificada para importação via Flutter.
    schema: Validação de entrada e transformação de features.
    train: Treino temporal com Random Forest.
    service: API FastAPI para inferência.
    demo: Geração de dados sintéticos para teste.
"""
