# FPU_SDII

Tipo de Valor|Sinal (S)|Expoente (E)|Mantissa (M)|Equação / Nota
-------------|---------|------------|------------|----------------
Zero (+)     |0        |Todos 0     |Todos 0     |Representa +0
Zero (-)     |1        |Todos 0     |Todos 0     |Representa −0
Infinito (+) |0        |Todos 1     |Todos 0     |Resultado de n/0
Infinito (-) |1        |Todos 1     |Todos 0     |Resultado de −n/0
NaN          |X        |Todos 1     |!= 0        |Ex: 0/0 ou −1​
Subnormais   |0 ou 1   |Todos 0     |!= 0        |Números muito próximos de zero
Normalizados |0 ou 1   |0 < E < 255 |Qlqr valor  |Números reais comuns
