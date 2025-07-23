@echo off
echo Inicializando repositorio Git y configurando remoto Celconex...

cd /d "%~dp0"

git init
git branch -M main
git remote add origin https://github.com/arturoochoa06/celconex-app.git
git add .
git commit -m "🚀 Commit inicial de estructura, documentación y sitio web"
git push -u origin main

echo.
echo Repositorio inicializado y publicado.
pause