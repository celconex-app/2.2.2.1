@echo off
echo Haciendo push de Celconex a GitHub...

cd /d "%~dp0"

git add .
git commit -m "📚 Subida inicial de documentación, sitio web y README"
git push origin main

echo.
echo ¡Listo! Verifica en GitHub: https://github.com/arturoochoa06/celconex-app
pause