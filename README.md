# winutils

Binaires Windows pour Apache Hadoop : `winutils.exe`, `hadoop.dll`, scripts `bin/` (`hadoop.cmd`, `hdfs.cmd`, etc.).

Format de sortie aligné sur [cdarlint/winutils](https://github.com/cdarlint/winutils) et [steveloughran/winutils](https://github.com/steveloughran/winutils).

## Build

Prérequis hôte : Docker uniquement.

```bash
./build.sh
./build.sh 3.4.2
./build.sh 3.5.0
```

Artefacts : `hadoop-<version>/bin/`

### Installation Docker (CachyOS / Arch)

```bash
sudo pacman -S docker
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
```

Reconnexion requise après ajout au groupe `docker`.

### Sources Hadoop

Le clone des sources Apache est effectué automatiquement dans `hadoop-src/` à partir du ref git défini dans `versions.conf`. Aucun téléchargement manuel.

### Nouvelle version

Ajouter une entrée dans `versions.conf` :

```
3.4.4=rel/release-3.4.4
```

```bash
./build.sh 3.4.4
```

Si la version est absente de `versions.conf`, le ref par défaut est `rel/release-<version>`.

### Options

| Option            | Action                           |
| ----------------- | -------------------------------- |
| `--rebuild-image` | Reconstruit l'image Docker       |
| `--shell`         | Ouvre un shell dans le conteneur |
| `-h`, `--help`    | Affiche l'aide                   |

### Caches

| Chemin                            | Contenu                                     |
| --------------------------------- | ------------------------------------------- |
| Image `winutils-hadoop-wine-msvc` | MSVC, Wine, JDK 8, Maven, vcpkg (bootstrap) |
| `.cache/vcpkg-installed/`         | Paquets vcpkg `x64-windows`                 |
| `~/.m2/repository`                | Artefacts Maven                             |
| `hadoop-src/`                     | Sources Hadoop clonées                      |

## Utilisation (Windows)

```cmd
set HADOOP_HOME=C:\chemin\vers\hadoop-3.4.1
set PATH=%PATH%;%HADOOP_HOME%\bin
```

## Licence

Les binaires (`hadoop-<version>/bin/`) sont compilés à partir d'[Apache Hadoop](https://hadoop.apache.org/), sous **Apache License 2.0** (ASF). Tu n'en es pas propriétaire : tu les redistribues selon les termes de cette licence, qui autorise usage, modification et redistribution (y compris commercial), avec obligation de conserver `LICENSE` et `NOTICE`.

Les scripts de build de ce dépôt sont sous la même licence (voir `LICENSE`, `NOTICE`).

Ce n'est pas du domaine public sans conditions : Apache 2.0 est une licence open source permissive, pas une renonciation totale aux droits de l'ASF sur Hadoop.

## Arborescence

```
build.sh
versions.conf
docker/
hadoop-<version>/bin/
hadoop-<version>/LICENSE
hadoop-<version>/NOTICE
hadoop-src/
.cache/vcpkg-installed/
```
