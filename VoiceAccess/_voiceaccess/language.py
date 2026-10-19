"""RoboDK-language messages and explicit punctuation for speech/AX labels.

Names in the station and visible labels stay intact. Only the spoken version
expands separators; signed coordinates use 'minus', model names use 'dash'.
"""

import re


# English is the source language. Unsupported RoboDK languages fall back to it.
# Each entry contains Catalan and Spanish, in that order.
MESSAGES = {
    "Station": ("Estació", "Estación"),
    "Robot": ("Robot", "Robot"),
    "Reference frame": ("Referència", "Referencia"),
    "Tool": ("Eina", "Herramienta"),
    "Object": ("Objecte", "Objeto"),
    "Target": ("Target", "Target"),
    "Curve": ("Corba", "Curva"),
    "Program": ("Programa", "Programa"),
    "Instruction": ("Instrucció", "Instrucción"),
    "Python program": ("Programa Python", "Programa Python"),
    "Machining project": ("Projecte de mecanitzat", "Proyecto de mecanizado"),
    "Folder": ("Carpeta", "Carpeta"),
    "Robot arm": ("Braç de robot", "Brazo de robot"),
    "Camera": ("Càmera", "Cámara"),
    "Item": ("Element", "Elemento"),
    "External axes": ("Eixos externs", "Ejes externos"),
    "Notes": ("Notes", "Notas"),
    "not available": ("no disponible", "no disponible"),
    "millimetres": ("mil·límetres", "milímetros"),
    "degrees": ("graus", "grados"),
    "Position": ("Posició", "Posición"),
    "Orientation Rx, Ry, Rz": ("Orientació Rx, Ry, Rz", "Orientación Rx, Ry, Rz"),
    "The item has changed or no longer exists. Refresh the station.": ("L'element ha canviat o ja no existeix. Actualitza l'estació.", "El elemento ha cambiado o ya no existe. Actualiza la estación."),
    "This instruction no longer exists. Refresh the program.": ("Aquesta instrucció ja no existeix. Actualitza el programa.", "Esta instrucción ya no existe. Actualiza el programa."),
    "Linear move to {destination}": ("Moviment lineal cap a {destination}", "Movimiento lineal hacia {destination}"),
    "Joint move to {destination}": ("Moviment articular cap a {destination}", "Movimiento articular hacia {destination}"),
    "Instruction {index} of {count} in program {name}.": ("Instrucció {index} de {count} del programa {name}.", "Instrucción {index} de {count} del programa {name}."),
    "{index} of {count}. {description}": ("{index} de {count}. {description}", "{index} de {count}. {description}"),
    "Coordinates relative to the reference frame used by this instruction.": ("Coordenades respecte de la referència utilitzada per la instrucció.", "Coordenadas respecto a la referencia utilizada por la instrucción."),
    "No station is open in RoboDK.": ("No hi ha cap estació oberta a RoboDK.", "No hay ninguna estación abierta en RoboDK."),
    "{count} instructions": ("{count} instruccions", "{count} instrucciones"),
    "Station {name}. {items} items and {programs} programs.": ("Estació {name}. {items} elements i {programs} programes.", "Estación {name}. {items} elementos y {programs} programas."),
    "Location": ("Ubicació", "Ubicación"),
    "TCP relative to the robot flange.": ("TCP respecte de la brida del robot.", "TCP respecto a la brida del robot."),
    "Coordinates relative to {name}.": ("Coordenades respecte de {name}.", "Coordenadas respecto a {name}."),
    "the station": ("l'estació", "la estación"),
    "Visible in the scene.": ("Visible a l'escena.", "Visible en la escena."),
    "Hidden in the scene.": ("Ocult a l'escena.", "Oculto en la escena."),
    "Joint target.": ("Target articular.", "Target articular."),
    "Cartesian target.": ("Target cartesià.", "Target cartesiano."),
    "Model joint values": ("Valors articulars del model", "Valores articulares del modelo"),
    "Joint units depend on the model kinematics.": ("Les unitats articulars depenen de la cinemàtica del model.", "Las unidades articulares dependen de la cinemática del modelo."),
    "Active reference frame": ("Referència activa", "Referencia activa"),
    "Active tool": ("Eina activa", "Herramienta activa"),
    "TCP position relative to the active reference frame.": ("Posició del TCP respecte de la referència activa.", "Posición del TCP respecto a la referencia activa."),
    "Contains {count} instructions.": ("Conté {count} instruccions.", "Contiene {count} instrucciones."),
    "Empty program, no instructions.": ("Programa buit, sense instruccions.", "Programa vacío, sin instrucciones."),
    "Associated robot": ("Robot associat", "Robot asociado"),
    "Running.": ("S'està executant.", "En ejecución."),
    "A simulation is already starting or running.": ("Ja s'està iniciant o executant una simulació.", "Ya se está iniciando o ejecutando una simulación."),
    "Idle.": ("En repòs.", "En reposo."),
    "Configured for the simulator.": ("Configurat per al simulador.", "Configurado para el simulador."),
    "Configured to run on the controller.": ("Configurat per executar-se al controlador.", "Configurado para ejecutarse en el controlador."),
    "Expand this program in the VoiceAccess tree to read its instructions.": ("Expandeix aquest programa a l'arbre de VoiceAccess per llegir les instruccions.", "Expande este programa en el árbol de VoiceAccess para leer sus instrucciones."),
    "Contains {count} direct children.": ("Conté {count} elements directes.", "Contiene {count} elementos directos."),
    "Reading and executing Python code is outside this prototype's scope.": ("La lectura del codi Python i la seva execució queden fora d'aquest prototip.", "La lectura y ejecución del código Python quedan fuera de este prototipo."),
    "Nothing is selected in RoboDK.": ("No hi ha cap element seleccionat a RoboDK.", "No hay ningún elemento seleccionado en RoboDK."),
    "No description is available for this selection.": ("Selecció sense descripció disponible.", "No hay una descripción disponible para esta selección."),
    "Running {name}.": ("S'està executant {name}.", "Ejecutando {name}."),
    "{name}. Step {index} of {count}. {instruction}.": ("{name}. Pas {index} de {count}. {instruction}.", "{name}. Paso {index} de {count}. {instruction}."),
    "{name}. {index} of {count}. {description}.": ("{name}. {index} de {count}. {description}.", "{name}. {index} de {count}. {description}."),
    "{name}. {index} of {count}. Execution finished or stopped.": ("{name}. {index} de {count}. Execució finalitzada o aturada.", "{name}. {index} de {count}. Ejecución finalizada o detenida."),
    "Execution progress": ("Progrés de l'execució", "Progreso de la ejecución"),
    "No simulation running.": ("No hi ha cap simulació en execució.", "No hay ninguna simulación en ejecución."),
    "The program": ("El programa", "El programa"),
    "{name}: execution finished or stopped.": ("{name}: execució finalitzada o aturada.", "{name}: ejecución finalizada o detenida."),
    "Select a simulation program in the VoiceAccess tree.": ("Selecciona un programa de simulació a l'arbre de VoiceAccess.", "Selecciona un programa de simulación en el árbol de VoiceAccess."),
    "RoboDK must be in simulation mode to use this button.": ("RoboDK ha d'estar en mode simulació per utilitzar aquest botó.", "RoboDK debe estar en modo simulación para utilizar este botón."),
    "Some programs are configured for the controller. This prototype only starts stations with every program in simulation mode.": ("Hi ha programes configurats per al controlador. Aquest prototip només inicia estacions amb tots els programes en simulació.", "Hay programas configurados para el controlador. Este prototipo solo inicia estaciones con todos los programas en simulación."),
    "VoiceAccess playback requires a station without Python programs. Use VoiceAccess-VoiceOver.rdk.": ("La reproducció des de VoiceAccess es limita a estacions sense programes Python. Utilitza VoiceAccess-VoiceOver.rdk.", "La reproducción desde VoiceAccess requiere una estación sin programas Python. Utiliza VoiceAccess-VoiceOver.rdk."),
    "The program is empty. There are no movements to execute.": ("El programa està buit. No hi ha cap moviment a executar.", "El programa está vacío. No hay movimientos que ejecutar."),
    "Simulating {name} at reduced speed to make narration easier to follow.": ("Simulant {name} a velocitat reduïda per facilitar-ne la lectura.", "Simulando {name} a velocidad reducida para facilitar la narración."),
    "This action is only available in the simulator.": ("Aquesta acció només està disponible al simulador.", "Esta acción solo está disponible en el simulador."),
    "Requested a stop for the simulation started from VoiceAccess.": ("S'ha demanat aturar la simulació iniciada des de VoiceAccess.", "Se ha solicitado detener la simulación iniciada desde VoiceAccess."),
    "Unknown VoiceAccess action.": ("Acció de VoiceAccess desconeguda.", "Acción de VoiceAccess desconocida."),
    "Connecting to RoboDK…": ("Connectant amb RoboDK…", "Conectando con RoboDK…"),
    "Listen to your station": ("Escolta l'estació", "Escucha tu estación"),
    "Refresh": ("Actualitza", "Actualizar"),
    "RoboDK selection": ("Selecció de RoboDK", "Selección de RoboDK"),
    "Read details": ("Llegeix detalls", "Leer detalles"),
    "Repeat": ("Repeteix", "Repetir"),
    "Silence": ("Silencia", "Silenciar"),
    "Status and last announcement": ("Estat i darrer avís", "Estado y último aviso"),
    "Find an item or instruction": ("Busca un element o una instrucció", "Buscar un elemento o instrucción"),
    "Focus station tree": ("Ves a l'arbre de l'estació", "Ir al árbol de la estación"),
    "Previous item": ("Element anterior", "Elemento anterior"),
    "Next item": ("Element següent", "Elemento siguiente"),
    "Expand item": ("Desplega l'element", "Expandir elemento"),
    "Collapse item": ("Plega l'element", "Contraer elemento"),
    "Expanded.": ("Desplegat.", "Expandido."),
    "Collapsed.": ("Plegat.", "Contraído."),
    "⌘↑↓ navigate · ⌘→ expand · ⌘← collapse · ⌘T tree · ⌘F find · ⌘L details\nVO+Shift+M item menu · ⌘B back to RoboDK · Esc silence.": ("⌘↑↓ navega · ⌘→ desplega · ⌘← plega · ⌘T arbre · ⌘F cerca · ⌘L detalls\nVO+Majúscules+M menú de l'element · ⌘B torna a RoboDK · Esc silencia.", "⌘↑↓ navegar · ⌘→ expandir · ⌘← contraer · ⌘T árbol · ⌘F buscar · ⌘L detalles\nVO+Mayúsculas+M menú del elemento · ⌘B volver a RoboDK · Esc silenciar."),
    "Use VO+Shift+Down to interact. Command+Down and Command+Up select the next and previous item from anywhere in this panel.": ("Entra-hi amb VO+Majúscules+Avall. Command+Avall i Command+Amunt seleccionen l'element següent i anterior des de qualsevol control del panell.", "Entra con VO+Mayúsculas+Abajo. Command+Abajo y Command+Arriba seleccionan el elemento siguiente y anterior desde cualquier control del panel."),
    "⌘T tree · ⌘↓ next item · ⌘↑ previous item · ⌘F find · ⌘L read details\n⌘S RoboDK selection · ⌘B back to RoboDK · Esc silence.": ("⌘T arbre · ⌘↓ element següent · ⌘↑ element anterior · ⌘F cerca · ⌘L llegeix detalls\n⌘S selecció de RoboDK · ⌘B torna a RoboDK · Esc silencia.", "⌘T árbol · ⌘↓ elemento siguiente · ⌘↑ elemento anterior · ⌘F buscar · ⌘L leer detalles\n⌘S selección de RoboDK · ⌘B volver a RoboDK · Esc silenciar."),
    "Items and instructions": ("Elements i instruccions", "Elementos e instrucciones"),
    "Station tree. Items and instructions": ("Arbre de l'estació. Elements i instruccions", "Árbol de la estación. Elementos e instrucciones"),
    "Selected item details": ("Detalls de l'element seleccionat", "Detalles del elemento seleccionado"),
    "Item description, coordinates and context": ("Descripció, coordenades i context de l'element", "Descripción, coordenadas y contexto del elemento"),
    "Own voice": ("Veu pròpia", "Voz propia"),
    "Speech output": ("Sortida de veu", "Salida de voz"),
    "Automatic": ("Automàtic", "Automático"),
    "Back to RoboDK": ("Torna a RoboDK", "Volver a RoboDK"),
    "Speech rate controls the local voice.": ("La velocitat controla la veu pròpia.", "La velocidad controla la voz propia."),
    "VoiceOver uses its own voice and speech rate.": ("VoiceOver utilitza la seva veu i velocitat.", "VoiceOver utiliza su propia voz y velocidad."),
    "VoiceOver is off. Turn it on or choose Own voice.": ("VoiceOver està apagat. Activa'l o tria Veu pròpia.", "VoiceOver está apagado. Actívalo o elige Voz propia."),
    "Follow RoboDK selection": ("Segueix la selecció de RoboDK", "Seguir la selección de RoboDK"),
    "Narrate simulation": ("Narra la simulació", "Narrar la simulación"),
    "Speech rate": ("Velocitat de la veu", "Velocidad de la voz"),
    "Slower": ("Més lent", "Más lento"),
    "Faster": ("Més ràpid", "Más rápido"),
    "Test voice": ("Prova la veu", "Probar la voz"),
    "{rate} words per minute": ("{rate} paraules per minut", "{rate} palabras por minuto"),
    "Own voice only; VoiceOver uses its own speech rate.": ("Només la veu pròpia; VoiceOver utilitza la seva velocitat.", "Solo la voz propia; VoiceOver utiliza su propia velocidad."),
    "Voice test. Model ABB IRB 120-3/0.6. X -12.5 millimetres.": ("Prova de veu. Model ABB IRB 120-3/0.6. X -12,5 mil·límetres.", "Prueba de voz. Modelo ABB IRB 120-3/0.6. X -12,5 milímetros."),
    "Simulate program": ("Simula programa", "Simular programa"),
    "Stop simulation": ("Atura simulació", "Detener simulación"),
    "⌘F find · ⌘R refresh · ⌘S read RoboDK selection · ⌘L read details · Esc silence.\nRoboDK's original menus and dialogs still require VoiceOver testing.": ("⌘F busca · ⌘R actualitza · ⌘S llegeix selecció · ⌘L llegeix detalls · Esc silencia.\nEls menús i diàlegs originals de RoboDK encara s'han de provar amb VoiceOver.", "⌘F buscar · ⌘R actualizar · ⌘S leer selección · ⌘L leer detalles · Esc silenciar.\nLos menús y diálogos originales de RoboDK aún requieren pruebas con VoiceOver."),
    "⌘F find · ⌘L read details · ⌘S RoboDK selection · ⌘B back to RoboDK · Esc silence.\nOpen this panel from RoboDK's VoiceAccess menu or an item's context menu.": ("⌘F busca · ⌘L llegeix detalls · ⌘S selecció de RoboDK · ⌘B torna a RoboDK · Esc silencia.\nObre el panell des del menú VoiceAccess de RoboDK o el menú contextual d'un element.", "⌘F buscar · ⌘L leer detalles · ⌘S selección de RoboDK · ⌘B volver a RoboDK · Esc silenciar.\nAbre el panel desde el menú VoiceAccess de RoboDK o el menú contextual de un elemento."),
    "Quit VoiceAccess": ("Surt de VoiceAccess", "Salir de VoiceAccess"),
    "Actions": ("Accions", "Acciones"),
    "Find an item": ("Busca un element", "Buscar un elemento"),
    "Refresh station": ("Actualitza estació", "Actualizar estación"),
    "Read RoboDK selection": ("Llegeix selecció de RoboDK", "Leer selección de RoboDK"),
    "Simulate selected program": ("Simula programa seleccionat", "Simular el programa seleccionado"),
    "Station loaded.": ("Estació carregada.", "Estación cargada."),
    "Could not complete the action.": ("No s'ha pogut completar l'acció.", "No se ha podido completar la acción."),
    "Could not start the connection": ("No s'ha pogut iniciar la connexió", "No se ha podido iniciar la conexión"),
    "The connection to RoboDK has closed. Reopen VoiceAccess from RoboDK.": ("La connexió amb RoboDK s'ha tancat. Torna a obrir VoiceAccess des de RoboDK.", "La conexión con RoboDK se ha cerrado. Vuelve a abrir VoiceAccess desde RoboDK."),
    "Could not send the action to RoboDK.": ("No s'ha pogut enviar l'acció a RoboDK.", "No se ha podido enviar la acción a RoboDK."),
}


def robodk_language(rdk):
    """Read, never set, the language of the connected RoboDK instance."""
    code = rdk.Command("Lang").strip().lower().replace("_", "-")
    return code if re.fullmatch(r"[a-z]{2}(?:-[a-z]{2})?", code) else "en"


class Language:
    def __init__(self, code="en"):
        self.robodk_code = code
        self.code = code.split("-")[0] if code.split("-")[0] in ("en", "ca", "es") else "en"

    def t(self, message, **values):
        translated = message
        if self.code in ("ca", "es") and message in MESSAGES:
            translated = MESSAGES[message][0 if self.code == "ca" else 1]
        return translated.format(**values)

    def spoken(self, text):
        minus, dash, slash, inside = {
            "en": ("minus", "dash", "slash", "then"),
            "ca": ("menys", "guió", "barra", "després"),
            "es": ("menos", "guion", "barra", "después"),
        }[self.code]
        text = re.sub(r"(?<![\w])[-−](?=\d)", f" {minus} ", text)
        text = re.sub(r"[-−–—]", f" {dash} ", text)
        text = text.replace("/", f" {slash} ").replace(">", f" {inside} ")
        return re.sub(r"[^\S\n]+", " ", text).strip()

    def output(self, value):
        """Attach speech equivalents without altering API names/display text."""
        if isinstance(value, list):
            return [self.output(child) for child in value]
        if isinstance(value, dict):
            result = {key: self.output(child) for key, child in value.items()}
            for source, target in (("text", "spoken_text"), ("label", "accessibility_label"), ("message", "spoken_message")):
                if source in result:
                    result[target] = self.spoken(result[source])
            return result
        return value

    def ui(self):
        # Unformatted templates are sent to AppKit, which substitutes {rate}.
        index = 0 if self.code == "ca" else 1
        return {key: values[index] if self.code != "en" else key for key, values in MESSAGES.items()}
