import requests
import socket
import os
import sys
import time
import json
from datetime import datetime

"""Funzione per loggare i messaggi sia su file che su console."""
def log_message(message):
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    log_entry = f"[{timestamp}] {message}"

    print(log_entry)

    script_dir = os.path.dirname(os.path.abspath(__file__))
    log_file = os.path.join(script_dir, 'log.txt')

    with open(log_file, 'a') as f:
        f.write(log_entry + '\n')

"""Ottiene il serial number della CPU del Raspberry Pi."""
def get_cpu_serial():
    try:
        with open('/proc/cpuinfo', 'r') as f:
            for line in f:
                if line.startswith('Serial'):
                    return line.split(':')[1].strip()
    except Exception as e:
        log_message(f"Errore nel leggere il serial number: {e}")
        return "unknown"

"""Ottiene l'indirizzo IP locale del dispositivo."""
def get_local_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        local_ip = s.getsockname()[0]
        s.close()
        return local_ip
    except Exception as e:
        log_message(f"Errore nel recuperare l'IP locale: {e}")
        return "unknown"

"""Invia il ping alla piattaforma."""
def send_ping():
    PLATFORM_URL = "http://192.168.5.83:3000/api/ping"
    DEFAULT_URL = "http://192.168.5.83:3000/welcome/"
    do_reboot = False

    try:
        payload = {
            "device_id": get_cpu_serial(),
            "local_ip": get_local_ip(),
            "timestamp": datetime.now().isoformat()
        }

        response = requests.post(PLATFORM_URL, json=payload, timeout=10)

        if response.status_code == 200:
            response_data = response.json()
            log_message("Ping inviato con successo")
            log_message(f"Risposta dal server: {json.dumps(response_data, indent=2)}")

            # Gestione del file fullpageos.txt
            fullpageos_file = '/boot/firmware/fullpageos.txt'
            device_id = get_cpu_serial()
            default_welcome_url = f"{DEFAULT_URL}{device_id}"

            try:
                # Leggi il contenuto attuale del file
                current_url_content = ""
                if os.path.exists(fullpageos_file):
                    with open(fullpageos_file, 'r') as f:
                        current_url_content = f.read().strip()

                # Ottieni il nuovo URL dalla risposta del server
                new_url_content = ""
                if ('device' in response_data and 
                    'data' in response_data['device'] and 
                    'url_content' in response_data['device']['data']):
                    new_url_content = response_data['device']['data']['url_content']

                # Decidi quale URL utilizzare
                url_to_write = ""
                if new_url_content:
                    url_to_write = new_url_content
                else:
                    url_to_write = default_welcome_url

                # Aggiorna il file solo se il contenuto è diverso
                if current_url_content != url_to_write:
                    log_message(f"Aggiornamento URL da '{current_url_content}' a '{url_to_write}'")
                    with open(fullpageos_file, 'w') as f:
                        f.write(url_to_write)
                    do_reboot = True
                else:
                    log_message("URL già aggiornato, nessuna modifica necessaria")

            except Exception as e:
                log_message(f"Errore nella gestione del file fullpageos.txt: {e}")

            # Salva la risposta in un file JSON
            script_dir = os.path.dirname(os.path.abspath(__file__))
            response_file = os.path.join(script_dir, 'response.json')
            with open(response_file, 'w') as f:
                json.dump(response_data, f, indent=2)

            if do_reboot:
                os.system("killall chromium")

        else:
            log_message(f"Errore nell'invio del ping. Status code: {response.status_code}")
            try:
                error_data = response.json()
                log_message(f"Dettagli errore: {json.dumps(error_data, indent=2)}")
            except:
                log_message("Impossibile leggere i dettagli dell'errore")

    except requests.exceptions.RequestException as e:
        log_message(f"Errore nella richiesta HTTP: {e}")
    except Exception as e:
        log_message(f"Errore generico: {e}")

"""Funzione principale che esegue il ping ogni 5 minuti."""
def main():
    log_message("Servizio di ping avviato")
    while True:
        send_ping()
        time.sleep(10)

if __name__ == "__main__":
    main()