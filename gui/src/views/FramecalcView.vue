<script setup lang="ts">
import CommandExplainer from "@/components/CommandExplainer";
import parseCommand from "@/components/CommandExplainer/CommandReader";
import type { Command } from "@/components/CommandExplainer/model";
import { reactive } from "vue";

const cmdName = "snartomo-framecalc";
const command = null as unknown as Command;

const state = reactive({
  command: command,
});
(async function () {
  const rest = await fetch("./framecalc-help.txt");
  const help = await rest.text();
  const cmd = parseCommand(help, cmdName);
  state.command = cmd;
})();
</script>

<template>
  <main>
    <CommandExplainer v-if="state.command" v-bind="state.command" />
  </main>
</template>
