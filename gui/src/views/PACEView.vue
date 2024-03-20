<script setup lang="ts">
import { reactive } from "vue";
import CommandExplainer from "@/components/CommandExplainer";
import parseCommand from "@/components/CommandExplainer/CommandReader";
import type { Command } from "@/components/CommandExplainer/model";

const cmdName = "snartomo-pace";
const command = { name: cmdName, groups: [] } as Command;

const state = reactive({
  command: command,
});
(async function () {
  const rest = await fetch("./pace-help.txt");
  const help = await rest.text();
  const cmd = parseCommand(help, cmdName);
  state.command = cmd;
})();
</script>

<template>
  <main>
    <CommandExplainer v-bind="state.command" />
  </main>
</template>
