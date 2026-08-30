# Les compteurs de limitation vivent dans leur propre cache mémoire, et non dans
# Rails.cache : l'environnement de test câble Rails.cache sur :null_store, ce qui ferait
# taire la limitation sans que rien ne le signale — une protection qu'on croit active et
# qui ne compte rien est pire que pas de protection du tout.
#
# Mémoire de processus, donc : la limite est celle d'UN processus Puma. En mode single
# (le cas ici, WEB_CONCURRENCY non défini) c'est exactement la limite annoncée. Passer à
# plusieurs workers la multiplierait d'autant ; il faudrait alors un store partagé.
module Milly
  RATE_LIMIT_STORE = ActiveSupport::Cache::MemoryStore.new(size: 4.megabytes)
end
