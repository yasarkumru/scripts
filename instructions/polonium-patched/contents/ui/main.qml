// main.qml - Entry point into script

import QtQuick;
import org.kde.kwin;

import "../code/main3.mjs" as Polonium;

Item {
    id: root;

    Timer {
        id: eventTimer;
    }
    
    Component.onCompleted: {
        const api = {
            "workspace": Workspace,
            "options": Options,
            "kwin": KWin,
            "console": console,
            "qt": Qt,
        };
        const qmlObjects = {
            "root": root,
            "eventTimer": eventTimer,
            "shortcuts": shortcutsLoader.item,
            "settings": settingsLoader.item,
            "dbus": dbusLoader.item,
        };
        Polonium.main(api, qmlObjects);
    }

    Loader {
        id: shortcutsLoader;
                
        source: "shortcuts.qml";
    }

    Loader {
        id: settingsLoader;
                
        source: "settings.qml";
    }
    
    Loader {
        id: dbusLoader;
        
        source: "dbus.qml";
    }
}
