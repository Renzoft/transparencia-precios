"""Utilidades de texto compartidas por los servicios."""
import unicodedata


def normalizar(texto: str) -> str:
    """Para comparar nombres sin que importen tildes, mayúsculas ni espacios dobles.

    «Limón Sutil » y «limon  sutil» quedan iguales. Se usa para reconocer variedades por
    su nombre y para detectar mercados repetidos.
    """
    sin_tildes = "".join(c for c in unicodedata.normalize("NFKD", texto)
                         if not unicodedata.combining(c))
    return " ".join(sin_tildes.lower().split())
