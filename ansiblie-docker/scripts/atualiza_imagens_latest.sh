#!/bin/bash

echo "🚀 Iniciando atualização automática de containers com imagem :latest (exceto bancos de dados)..."

LIMITE_TEMPO=$((90 * 24 * 60 * 60))
AGORA=$(date +%s)

# Palavras-chave de imagens que queremos ignorar (bancos)
IGNORAR="mysql|mariadb|postgres|mongo|redis"

containers=$(docker ps -a --format "{{.ID}} {{.Image}}" | grep ':latest')

while IFS= read -r linha; do
    container_id=$(echo "$linha" | awk '{print $1}')
    imagem=$(echo "$linha" | awk '{print $2}')

    # Ignorar bancos
    if echo "$imagem" | grep -Eiq "$IGNORAR"; then
        echo "⏭️ Ignorando imagem de banco de dados: $imagem"
        continue
    fi

    imagem_id=$(docker inspect --format='{{.Image}}' "$container_id")
    imagem_criada=$(docker inspect --format='{{.Created}}' "$imagem_id")
    imagem_timestamp=$(date -d "$imagem_criada" +%s 2>/dev/null)

    if [ -z "$imagem_timestamp" ]; then
        echo "⚠️ Falha ao verificar a data da imagem $imagem"
        continue
    fi

    tempo_passado=$((AGORA - imagem_timestamp))

    if [ "$tempo_passado" -gt "$LIMITE_TEMPO" ]; then
        echo ""
        echo "🧨 Atualizando container: $container_id"
        echo "   Imagem antiga: $imagem"
        echo "   Criada há: $((tempo_passado / 86400)) dias"

        # Extrai os argumentos atuais com inspect
        cmd=$(docker inspect "$container_id" | jq -r '.[0].Config.Cmd | join(" ")')
        portas=$(docker port "$container_id" | awk '{print "-p "$3":"$1}')
        nome=$(docker inspect --format '{{.Name}}' "$container_id" | sed 's/\///')
        volumes=$(docker inspect "$container_id" | jq -r '.[0].Mounts[] | "-v \(.Source):\(.Destination)"')
        restart=$(docker inspect "$container_id" | jq -r '.[0].HostConfig.RestartPolicy.Name')
        restart_flag=""
        [ "$restart" != "no" ] && restart_flag="--restart=$restart"

        echo "   Parando e removendo container antigo..."
        docker stop "$container_id" && docker rm "$container_id"

        echo "   Removendo imagem antiga..."
        docker rmi "$imagem"

        echo "   Puxando nova imagem..."
        docker pull "$imagem"

        echo "   Subindo novo container com as mesmas configurações..."
        docker run -d \
            $portas \
            $volumes \
            --name "$nome" \
            $restart_flag \
            "$imagem" \
            $cmd

        echo "✅ Container '$nome' atualizado com sucesso!"
        echo ""
    fi
done <<< "$containers"

echo "🧼 Finalizado."
