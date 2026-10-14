"""Límite de peticiones por cliente (Especificación de Endpoints, «Límite de peticiones»).

Protege la cuota diaria de OpenRouteService: solo se aplica a los endpoints que la
consumen, POST /comparaciones y POST /direcciones. Una persona que compara mercados no
necesita más de unas pocas consultas por minuto; un script que las repite sin pausa
agotaría la cuota de todos.

El conteo vive en la memoria del proceso: basta para una sola instancia de la API.

Al desplegar detrás de un proxy (Render), la IP del cliente llega en X-Forwarded-For:
uvicorn debe iniciarse con --proxy-headers para que request.client sea la del usuario y
no la del proxy.
"""
import time
from collections import defaultdict, deque
from threading import Lock

from fastapi import Request

from app.core.errores import ErrorAPI


class LimitePeticiones:
    def __init__(self, maximo: int, ventana_s: float = 60.0):
        self.maximo = maximo
        self.ventana_s = ventana_s
        self._marcas: dict[str, deque] = defaultdict(deque)
        self._candado = Lock()

    def permitir(self, cliente: str) -> bool:
        ahora = time.monotonic()
        with self._candado:
            marcas = self._marcas[cliente]
            while marcas and ahora - marcas[0] >= self.ventana_s:
                marcas.popleft()
            if len(marcas) >= self.maximo:
                return False
            marcas.append(ahora)
            return True

    def reiniciar(self) -> None:
        with self._candado:
            self._marcas.clear()

    def __call__(self, request: Request) -> None:
        """Dependencia de FastAPI: responde 429 si el cliente superó el límite."""
        cliente = request.client.host if request.client else "desconocido"
        if not self.permitir(cliente):
            raise ErrorAPI(429, "DEMASIADAS_PETICIONES", "Hiciste muchas consultas seguidas. "
                           "Espera un minuto e inténtalo de nuevo.")


limite_comparaciones = LimitePeticiones(maximo=10)
limite_direcciones = LimitePeticiones(maximo=20)
